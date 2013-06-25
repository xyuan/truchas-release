/* *************************************************************************** *
*                                                                              *
*                                                                              *
*                             Copyright  (C) 20xx,                             *
*                      Los Alamos National Security, LLC                       *
*                                                                              *
*                             LA-CC-xxxxxx                                     *
*                                                                              *
* **************************************************************************** */

/*
 *  
 * General Python Interface Utilities
 *
 */
#include <Python.h>

#include "DanuPyException.h"
#include "DanuPyUtils.h"

PyObject * convertCharListToPyList(const char * const * names, int num)
{
  PyObject *list = NULL;
  int err;
  Py_ssize_t idx;
  Py_ssize_t py_num = (Py_ssize_t) num;

  if ( num >= 0 ) {
    list = PyList_New(py_num);
    idx = 0;
    err = 0;
    while ( (idx < num) && ( err == 0 )) {
      err = PyList_SetItem(list,idx,PyString_FromString(names[idx]));
      idx++;
    }
  }

  return list;
}

PyObject * buildPyList(PyObject **objects, int num)
{
  PyObject *list=NULL;
  Py_ssize_t idx, py_num;

  if ( num < 0) {
    throw_exception("Incorrect list length in buildPyList");
    return NULL;
  }

  py_num=(Py_ssize_t)num;
  list=PyList_New(py_num);
  for(idx=0;idx<py_num;idx++) {
    Py_INCREF(objects[idx]);
    PyList_SET_ITEM(list,idx,objects[idx]);
  }

  return list;
}





    

