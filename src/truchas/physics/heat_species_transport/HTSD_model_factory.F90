!!
!! HTSD_MODEL_FACTORY
!!
!! This module provides a method for initializing an instance of an HTSD_MODEL
!! variable.  It depends essentially on Truchas-specific input data, and
!! encapsulates all the gory details of how the components of the HTSD_MODEL
!! object are defined.  This is also where the bulk of the HT/SD model
!! verification is done.
!!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!
!! Copyright (c) Los Alamos National Security, LLC.  This file is part of the
!! Truchas code (LA-CC-15-097) and is subject to the revised BSD license terms
!! in the LICENSE file found in the top-level directory of this distribution.
!!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!
!! PROGRAMMING INTERFACE
!!
!!  CREATE_HTSD_MODEL (DISC, MMF, STAT, ERRMSG) returns a pointer to a new,
!!    fully-defined, HTSD_MODEL-type object.  DISC is a pointer to the MFD
!!    discretization and MMF is a pointer to a corresponding material mesh
!     function.  The integerSTAT returns a non-zero value if an error is
!!    encountered, and an explanatory message is returned in the character
!!    string ERRMSG.
!!

#include "f90_assert.fpp"

module HTSD_model_factory

  use HTSD_model_type
  use unstr_mesh_type
  use mfd_disc_type
  use matl_mesh_func_type
  implicit none
  private

  public :: create_HTSD_model

contains

  function create_HTSD_model (disc, mmf, stat, errmsg) result (model)

    use diffusion_solver_data, only: heat_eqn, num_species
    use property_data_module, only: void_temperature
    use material_interop, only: void_material_index

    type(mfd_disc), intent(in), target :: disc
    type(matl_mesh_func), intent(in), target :: mmf
    integer, intent(out) :: stat
    character(*), intent(out) :: errmsg
    type(HTSD_model), pointer :: model

    type(HT_model), pointer :: htmodel => null()
    type(SD_model), pointer :: sdmodel(:) => null()
    type(unstr_mesh), pointer :: mesh

    mesh => disc%mesh

    if (heat_eqn) then
      htmodel => create_HT_model(mesh, mmf, stat, errmsg)
      if (stat /= 0) return
    endif

    if (num_species > 0) then
      sdmodel => create_SD_model(mesh, mmf, stat, errmsg)
      if (stat /= 0) return
    end if

    allocate(model)
    call HTSD_model_init (model, disc, htmodel, sdmodel)
    
    if (heat_eqn .and. void_material_index > 0) model%void_temp = void_temperature(void_material_index)

  end function create_HTSD_model

  function create_HT_model (mesh, mmf, stat, errmsg) result (model)

    use rad_problem_type

    type(unstr_mesh), intent(in), target :: mesh
    type(matl_mesh_func), intent(in), target :: mmf
    integer, intent(out) :: stat
    character(*), intent(out) :: errmsg
    type(HT_model), pointer :: model

    allocate(model)

    !! Initializes the VF_RAD_PROB components of MODEL.
    model%vf_rad_prob => create_vf_rad_prob(mesh, stat, errmsg)
    if (stat /= 0) return

    !! Defines the equation parameter components of MODEL.
    call define_system_parameters (mesh, mmf, model, stat, errmsg)
    if (stat /= 0) return

    !! Defines the boundary condition components of MODEL.
    call define_system_bc (mesh, model, stat, errmsg)
    if (stat /= 0) return

  contains

    subroutine define_system_parameters (mesh, mmf, model, stat, errmsg)

      use phase_property_table
      use material_utilities
      use matl_mesh_func_type
      use property_mesh_function
      use ds_source_input, only: define_external_source
      use parallel_communication, only: global_any

      type(unstr_mesh), intent(in), target :: mesh
      type(matl_mesh_func), intent(in), target :: mmf
      type(HT_model), intent(inout) :: model
      integer, intent(out) :: stat
      character(len=*), intent(out) :: errmsg

      integer, allocatable :: matid(:)

      !! Retrieve a list of all the material IDs that may be encountered.
      call mmf%get_all_matl(matid, drop_void=.true.)

      !! Enthalpy density.
      call required_property_check (matid, 'enthalpy density', stat, errmsg)
      if (stat /= 0) return
      call pmf_create (model%H_of_T, mmf, ppt_property_id('enthalpy density'), stat, errmsg)
      if (global_any(stat /= 0)) then
        stat = -1
        errmsg = 'unexpected error defining H_of_T: ' // trim(errmsg)
        return
      end if

      !! Thermal conductivity.
      call required_property_check (matid, 'conductivity', stat, errmsg)
      if (stat /= 0) return
      call pmf_create (model%conductivity, mmf, ppt_property_id('conductivity'), stat, errmsg)
      !call pmf_set_harmonic_average (model%conductivity)
      if (global_any(stat /= 0)) then
        stat = -1
        errmsg = 'unexpected error defining conductivity: ' // trim(errmsg)
        return
      end if

      !! External heat source.
      call define_external_source (mesh, 'temperature', model%source)

      stat = 0
      errmsg = ''

    end subroutine define_system_parameters

    subroutine define_system_bc (mesh, model, stat, errmsg)

      use ds_boundary_condition_input, only: get_boundary_data
      use ds_interface_condition_input, only: get_interface_data
      use evaporation_namelist, only: evap_params => params
      use evap_heat_flux_type
      use index_partitioning, only: gather_boundary
      use bitfield_type
      use physical_constants, only: stefan_boltzmann, absolute_zero
      use parallel_communication, only: global_all, global_any, global_count
      use string_utilities, only: i_to_c

      type(unstr_mesh), intent(in), target :: mesh
      type(HT_model), intent(inout) :: model
      integer, intent(out) :: stat
      character(len=*), intent(out) :: errmsg

      integer :: j, n
      logical, allocatable :: mask(:), rmask(:), fmask(:)
      integer, allocatable :: setids(:)
      character(len(errmsg)) :: string1, string2
      character(:), allocatable :: errmsg2
      type(bitfield) :: bitmask
      type(evap_heat_flux), allocatable :: evap_flux

      allocate(mask(mesh%nface))

      mask = .false.

      !! Define the internal HTC interface conditions.
      call get_interface_data (mesh, 'temperature', 'HTC', 1, model%ic_htc)
      mask(model%ic_htc%faces(1,:)) = .true.
      mask(model%ic_htc%faces(2,:)) = .true.
      call gather_boundary (mesh%face_ip, mask)
      
      !! Define the gap radiation interface conditions;
      !! may be superimposed with HTC conditions.
      call get_interface_data (mesh, 'temperature', 'radiation', 1, model%ic_rad)
      mask(model%ic_rad%faces(1,:)) = .true.
      mask(model%ic_rad%faces(2,:)) = .true.
      call gather_boundary (mesh%face_ip, mask)

      !! Flux-type boundary conditions.  These may be superimposed.
      allocate(fmask(mesh%nface))
      fmask = .false.

      !! Define the simple flux boundary conditions.
      call get_boundary_data (mesh, 'temperature', 'flux', 1, model%bc_flux)
      if (global_any(mask(model%bc_flux%faces))) then
        stat = -1
        errmsg = 'temperature flux boundary condition overlaps with interface conditions'
        return
      end if
      fmask(model%bc_flux%faces) = .true. ! mark the simple flux faces

      !! Define the external HTC boundary conditions.
      call get_boundary_data (mesh, 'temperature', 'HTC', 2, model%bc_htc)
      if (global_any(mask(model%bc_htc%faces))) then
        stat = -1
        errmsg = 'temperature HTC boundary condition overlaps with interface conditions'
        return
      end if
      fmask(model%bc_htc%faces) = .true. ! mark the HTC faces

      !! Tag all the enclosure radation (view factor) faces.  They were already
      !! verified to be boundary faces and non-overlapping with each other.
      allocate(rmask(mesh%nface))
      rmask = .false.
      if (associated(model%vf_rad_prob)) then
        do j = 1, size(model%vf_rad_prob)
          rmask(model%vf_rad_prob(j)%faces) = .true.
          fmask(model%vf_rad_prob(j)%faces) = .true.
        end do
        call gather_boundary (mesh%face_ip, rmask)
        call gather_boundary (mesh%face_ip, fmask)
      end if

      !! Define the (simple) radiation boundary conditions.
      call get_boundary_data (mesh, 'temperature', 'radiation', 2, model%bc_rad)
      if (global_any(rmask(model%bc_rad%faces))) then
        stat = -1
        errmsg = 'temperature radiation boundary condition overlaps with enclosure radiation'
        return
      end if
      deallocate(rmask)
      if (global_any(mask(model%bc_rad%faces))) then
        stat = -1
        errmsg = 'temperature radiation boundary condition overlaps with interface conditions'
        return
      end if
      fmask(model%bc_rad%faces) = .true. ! mark the radiation faces
      model%sbconst = stefan_boltzmann
      model%abszero = absolute_zero

      !! Define the evaporation heat flux boundary condition
      if (allocated(evap_params)) then
        allocate(evap_flux)
        call evap_flux%init(mesh, evap_params, stat, errmsg2)
        if (stat /= 0) then
          errmsg = errmsg2
          return
        end if
        if (.not.global_all(fmask(evap_flux%index))) then
          stat = -1
          errmsg = 'evaporation heat flux applied to non-flux boundary'
          return
        end if
        call move_alloc(evap_flux, model%evap_flux)
      end if

      !! Merge flux mask into main mask.
      mask = mask .or. fmask
      deallocate(fmask)

      !! Define the Dirichlet boundary conditions.
      call get_boundary_data (mesh, 'temperature', 'dirichlet', 1, model%bc_dir)
      if (global_any(mask(model%bc_dir%faces))) then
        stat = -1
        errmsg = 'temperature dirichlet boundary condition overlaps with other conditions'
        return
      end if
      mask(model%bc_dir%faces) = .true. ! mark the dirichlet faces

      !! Finally verify that a condition has been applied to every boundary face.
      mask = mask .neqv. btest(mesh%face_set_mask,0)
      if (global_any(mask)) then
        call mesh%get_face_set_ids(pack([(j,j=1,mesh%nface)], mask), setids)
        if (size(setids) == 0) then
          string1 = ' (none)'
        else
          write(string1,'(i0,*(:,", ",i0))') setids
        end if
        call mesh%get_link_set_ids(mask, setids)
        if (size(setids) == 0) then
          string2 = ' (none)'
        else
          write(string2,'(i0,*(:,", ",i0))') setids
        end if
        errmsg = 'incomplete temperature boundary/interface specification;' // &
            ' remaining boundary faces belong to face sets ' // trim(string1) // &
            '; and interface link sets ' // trim(string2)
        bitmask = ibset(ZERO_BITFIELD, 0)
        mask = mask .and. (mesh%face_set_mask == bitmask)
        mask(mesh%lface(1,:)) = .false.
        mask(mesh%lface(2,:)) = .false.
        n = global_count(mask(:mesh%nface_onP))
        if (n > 0) errmsg = trim(errmsg) // '; ' // i_to_c(n) // ' faces belong to neither'
        stat = -1
        return
      end if

      stat = 0
      errmsg = ''

    end subroutine define_system_bc

  end function create_HT_model

  function create_vf_rad_prob (mesh, stat, errmsg) result (vf_rad_prob)

    use rad_problem_type
    use ER_input
    use bitfield_type, only: btest
    use parallel_communication, only: global_any, global_all

    type(unstr_mesh), intent(in) :: mesh
    integer, intent(out) :: stat
    character(len=*), intent(out) :: errmsg
    type(rad_problem), pointer :: vf_rad_prob(:)

    integer :: n, j
    logical, allocatable :: mask(:)
    character(len=31), allocatable :: encl_name(:)

    stat = 0
    errmsg = ''

    !! Initialize the enclosure radiation (view factor) problems, if any.
    n = ERI_num_enclosures()
    if (n > 0) then
      allocate(vf_rad_prob(n), encl_name(n))
      call ERI_get_names (encl_name)
      do j = 1, n
        call vf_rad_prob(j)%init (mesh, encl_name(j))
        !! Verify that these enclosure faces are boundary faces.
        if (.not.global_all(btest(mesh%face_set_mask(vf_rad_prob(j)%faces),0))) then
          stat = -1
          errmsg = 'some enclosure faces are not boundary faces'
          exit
        else if (n > 1) then  ! multiple enclosures
          if (j == 1) then
            allocate(mask(mesh%nface))
            mask = .false.
          !! Verify that these faces don't overlap with other enclosure faces.
          else if (global_any(mask(vf_rad_prob(j)%faces))) then
            stat = -1
            errmsg = 'some enclosure faces belong to other enclosures'
            exit
          !! Tag the faces belonging to this enclosure.
          else
            mask(vf_rad_prob(j)%faces) = .true.
          end if
        end if
      end do
      if (allocated(mask)) deallocate(mask)
      deallocate(encl_name)
    else
      vf_rad_prob => null()
    end if

  end function create_vf_rad_prob

  function create_SD_model (mesh, mmf, stat, errmsg) result (model)

    use diffusion_solver_data, only: num_species, heat_eqn
    use phase_property_table
    use property_mesh_function
    use material_utilities
    use ds_source_input, only: define_external_source
    use ds_boundary_condition_input, only: get_boundary_data
    use bitfield_type, only: btest
    use index_partitioning
    use parallel_communication, only: global_any

    type(unstr_mesh), intent(in), target :: mesh
    type(matl_mesh_func), intent(in), target :: mmf
    integer, intent(out) :: stat
    character(*), intent(out) :: errmsg
    type(SD_model), pointer :: model(:)

    integer :: n, j
    logical :: mask(mesh%nface)
    character(len=31) :: property, variable
    integer, allocatable :: setids(:), matids(:)

    allocate(model(num_species))

    !! Define the equation parameter components of MODEL.
    call mmf%get_all_matl(matids, drop_void=.true.)
    do n = 1, num_species
      write(variable,'(a,i0)') 'concentration', n
      write(property,'(a,i0)') 'diffusivity', n
      call required_property_check (matids, property, stat, errmsg)
      if (stat /= 0) return
      call pmf_create (model(n)%diffusivity, mmf, ppt_property_id(property), stat, errmsg)
      if (global_any(stat /= 0)) then
        stat = -1
        errmsg = 'unexpected error defining diffusivity: ' // trim(errmsg)
        return
      end if
      call define_external_source (mesh, variable, model(n)%source)
      !! Define the optional Soret effect coefficients.
      if (heat_eqn) then
        write(property,'(a,i0)') 'soret', n
        call optional_property_check (matids, property, stat, errmsg)
        if (stat < 0) return
        if (stat == 0) then ! this property was defined
          allocate(model(n)%soret)
          call pmf_create (model(n)%soret, mmf, ppt_property_id(property), stat, errmsg)
          if (stat /= 0) return
        end if
      end if
    end do

    !! Define the boundary condition components of MODEL.
    do n = 1, num_species
      write(variable,'(a,i0)') 'concentration', n
      mask = .false.  ! used to tag faces where a BC has been applied
      !! Define the Dirichlet BC object for this concentration component.
      call get_boundary_data (mesh, variable, 'dirichlet', 1, model(n)%bc_dir)
      mask(model(n)%bc_dir%faces) = .true.  ! tag the Dirichlet BC faces
      !! Define the flux BC object for this concentration component.
      call get_boundary_data (mesh, variable, 'flux', 1, model(n)%bc_flux)
      !! Verify the flux BC faces don't overlap with preceding BC faces.
      if (global_any(mask(model(n)%bc_flux%faces))) then
        stat = -1
        errmsg = trim(variable) // ': flux BC overlaps with other BC!'
        return
      end if
      mask(model(n)%bc_flux%faces) = .true. ! tag the flux BC faces
      !! Finally verify that a BC has been applied to every boundary face.
      if (global_any(mask.neqv.btest(mesh%face_set_mask,0))) then
        mask = mask .neqv. btest(mesh%face_set_mask,0)
        call mesh%get_face_set_IDs (pack([(j,j=1,mesh%nface)], mask), setids)
        stat = -1
        !! The assumption here is that no bad faces are internal; any errors of
        !! that kind should have been caught when creating the bd_data objects.
        write(errmsg,'(a,99(:,1x,i0))') &
          trim(variable) // ': incomplete BC specification; ' // &
          'remaining boundary faces belong to face sets', setids
        deallocate(setids)
        return
      end if
    end do
    
    stat = 0
    errmsg = ''

  end function create_SD_model

end module HTSD_model_factory
