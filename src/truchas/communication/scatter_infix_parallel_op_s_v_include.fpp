! Include this file for scatters with op, where op is an inline (infix) operator
! Before including this file, define _INFIX_OP_ to be the operator of choice
! This is the parallel version.


#ifndef _ROUTINE_NAME_
#error "_ROUTINE_NAME_ must be defined before including this file."
#endif

#ifndef _DATA_TYPE_
#error "_DATA_TYPE_ must be defined before including this file."
#endif

#ifndef _OP_ID_
#error "_OP_ID_ must be defined before including this file."
#endif

#ifdef _PLUS_
#define _INFIX_OP_ +
#endif

#ifdef _OR_
#define _INFIX_OP_ .OR.
#endif

#ifndef _INFIX_OP_
#error "An infix operator must be defined before including this file."
#define _INFIX_OP_ __NOP__
#endif

  SUBROUTINE _ROUTINE_NAME_ (Dest, Src, Mesh, TYPE, TRACE, BOUNDARY, MASK)
    use mesh_module,  only: MESH_CONNECTIVITY

    ! Arguments
    _DATA_TYPE_             , dimension(:),                          &
         intent(INOUT)                          :: Dest
    _DATA_TYPE_             , dimension(:,:),                        &
         intent(IN)                             :: Src
    type(MESH_CONNECTIVITY),  dimension(SIZE(Src,2)),                &
         intent(IN)                             :: Mesh
    _DATA_TYPE_             , dimension(:),                          &         
                              POINTER,                               &
                              OPTIONAL                               :: BOUNDARY
    logical,                  dimension(:,:),&
                              intent(IN ),                           &
                              OPTIONAL                               :: MASK
    type (COMM_TYPE),         intent(IN   )                          :: TYPE

    type (PGSLib_GS_Trace), POINTER :: Trace

    ! Local scalars & arrays
    integer :: v, n, f, c
    logical :: PRESENT_MASK, TEMP_BOUNDARY, NEW_BOUNDARY
    _DATA_TYPE_, POINTER,  Dimension(:) :: Supplement_Data
    _DATA_TYPE_, POINTER,  dimension(:) :: Duplicate_Data

    ! <><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>

    PRESENT_MASK = PRESENT(MASK)

    ! If BOUNDARY is not passed in, then we have to use a local
    ! boundaray.  If BOUNDARY is passed in, then if it is NULL
    ! we have to allocate space.  In either case, if we allocate
    ! we have to do a global scatter.  If BOUNDARY is passed in
    ! and is associated, we assume it is the right size and
    ! use it for duplicate_data.

    ! Do we use local boundary, are use user provided boundary?
    TEMP_BOUNDARY = .NOT. PRESENT(BOUNDARY)

    ! If the BOUNDARY is associated, use it, otherwise get new boundary data.
    IF (TEMP_BOUNDARY) THEN
       NEW_BOUNDARY   = .TRUE.
    ELSE
       NEW_BOUNDARY   = .NOT. ASSOCIATED(BOUNDARY)
    ENDIF

    ! Initialize the supplement buffer since we will be accumulating into it.
    ALLOCATE(Supplement_Data(PGSLib_Size_Of_Sup(Trace)))
    Supplement_Data = _OP_ID_

    ! Scatter locally, into local mesh or supplement data comm buffer.
    ! loop because of possibility of data collisions
    SELECT CASE(Type%Type)
    CASE(EE%Type)
       IF (PRESENT_MASK) THEN
          do c = 1,SIZE(Mesh,1)                  ! Loop over cells
             do f = 1,SIZE(Mesh(1)%Ngbr_cell,1)  ! Loop over faces

                IF (.NOT. MASK(f, c)) CYCLE

                IF ( Mesh(c)%Ngbr_cell(f) > 0) then
                   Dest(Mesh(c)%Ngbr_cell(f)) = Dest(Mesh(c)%Ngbr_cell(f)) _INFIX_OP_ Src(f,c)
                ELSE
                   Supplement_Data( -Mesh(c)%Ngbr_cell(f)) = &
                        &  Supplement_Data( -Mesh(c)%Ngbr_cell(f)) _INFIX_OP_ Src(f,c)
                ENDIF
             end do
          end do
       ELSE
          do c = 1,SIZE(Mesh,1)                  ! Loop over cells
             do f = 1,SIZE(Mesh(1)%Ngbr_cell,1)  ! Loop over faces

                IF (MEsh(c)%Ngbr_cell(f) > 0) then
                   Dest(Mesh(c)%Ngbr_cell(f)) = Dest(Mesh(c)%Ngbr_cell(f)) _INFIX_OP_ Src(f,c)
                ELSE
                   Supplement_Data(-Mesh(c)%Ngbr_cell(f)) = &
                        &  Supplement_Data(-Mesh(c)%Ngbr_cell(f)) _INFIX_OP_ Src(f,c)
                ENDIF

             end do
          end do
       ENDIF

    CASE(EN%Type)
       IF (PRESENT_MASK) THEN
          do c = 1,SIZE(Mesh,1)                 ! Loop over cells
             do v = 1,SIZE(Mesh(1)%Ngbr_vrtx,1) ! Loop over vertices

                IF (.NOT. Mask(v,c)) CYCLE

                IF (Mesh(c)%Ngbr_vrtx(v) > 0) then
                   Dest(Mesh(c)%Ngbr_vrtx(v)) = Dest(Mesh(c)%Ngbr_vrtx(v)) _INFIX_OP_ Src(v,c)
                ELSE
                   Supplement_Data(-Mesh(c)%Ngbr_vrtx(v)) = &
                        &  Supplement_Data(-Mesh(c)%Ngbr_vrtx(v)) _INFIX_OP_ Src(v,c)
                ENDIF

             end do
          end do

       ELSE
          do c = 1,SIZE(Mesh,1)                 ! Loop over cells
             do v = 1,SIZE(Mesh(1)%Ngbr_vrtx,1) ! Loop over vertices

                IF (Mesh(c)%Ngbr_vrtx(v) > 0 ) then
                   Dest(Mesh(c)%Ngbr_vrtx(v)) = Dest(Mesh(c)%Ngbr_vrtx(v)) _INFIX_OP_ Src(v,c)
                ELSE
                   Supplement_Data( -Mesh(c)%Ngbr_vrtx(v)) = &
                        &  Supplement_Data( -Mesh(c)%Ngbr_vrtx(v)) _INFIX_OP_ Src(v,c)
                ENDIF

             end do
          end do
       ENDIF
    END SELECT


    IF (NEW_BOUNDARY) THEN
       ALLOCATE(Duplicate_Data(PGSLib_Size_Of_Dup(Trace)))
       ! If we were passed in a boundary, and it wasn't allocated
       ! then point boundary at newly allocated Duplicate_Data and save it
       IF (.NOT. TEMP_BOUNDARY) BOUNDARY => Duplicate_Data

       ! The communication, takes data from Supplement buffer, puts data into Duplicate buffer
       Duplicate_Data = _OP_ID_
       Duplicate_Data = PGSLib_Scatter_Buffer(Supplement_Data, Trace)
    ELSE
       ! If we were passed in a boundary, and it was allocated already,
       ! then us it
       IF (.NOT. TEMP_BOUNDARY) Duplicate_Data => BOUNDARY 

       IF (SIZE(Duplicate_Data,1) /= PGSLib_Size_Of_Dup(Trace)) THEN
          call TLS_panic ('SCATTER: wrong size boundary data')
       END IF
    END IF

    ! Finally, scatter Duplicate buffer into local mesh
    ! Notice the role of the mask.  Since it is a source mask, the mask
    ! plays no role at this end.  Since Duplicate_Data was initialized with
    ! _OP_ID_ any masked elements have no effect.
    DO n= 1, PGSLib_Size_Of_Dup(Trace)
       Dest(PGSLib_Dup_Index(Trace, n)) = Dest(PGSLib_Dup_Index(Trace, n)) _INFIX_OP_ &
            &                             Duplicate_Data(n)
    ENDDO

    ! Clean Up
    DEALLOCATE(Supplement_Data)
    ! If BOUNDARY was not passed in, then deallocate space provided
    IF (TEMP_BOUNDARY) DEALLOCATE(Duplicate_Data)
    return

  END SUBROUTINE _ROUTINE_NAME_

#undef _ROUTINE_NAME_
#undef _INFIX_OP_
#undef _OP_ID_
#undef _DATA_TYPE_

