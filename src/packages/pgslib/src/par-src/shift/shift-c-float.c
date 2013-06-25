/* C routines to support physical shift routines */

/* $Id: shift-c-float.c,v 1.1.1.1 2000/10/11 22:44:23 ferrell Exp $ */

#include "mpi.h"
#include "pgslib-include-c.h"

#define PGSLIB_DATA_TYPE     float
#define SIZE_MULTIPLIER      1
#define PGSLIB_ROUTINE_NAME  physical_c_shift_up_ ## float_c
#define PGSLIB_MPI_DATA_TYPE MPI_FLOAT

#define _DIRECTION_SIGN_ +

#include "shift-c.h"

/**********************************************************************/

#define PGSLIB_DATA_TYPE     float
#define SIZE_MULTIPLIER      1
#define PGSLIB_ROUTINE_NAME  physical_c_shift_down_ ## float_c
#define PGSLIB_MPI_DATA_TYPE MPI_FLOAT

#define _DIRECTION_SIGN_ -

#include "shift-c.h"


