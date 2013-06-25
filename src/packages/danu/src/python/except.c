/* Exception Handling Code for SWIG wrappers */

#include <string.h>

#define DANU_PYTHON_OK    0
#define DANU_PYTHON_FAIL -1
#define MAX_ERROR_MESSAGE 256

static char error_message[MAX_ERROR_MESSAGE];
static int error_status = 0;

void throw_exception(char *msg) {
  strncpy(error_message,msg,MAX_ERROR_MESSAGE);
  error_status = DANU_PYTHON_FAIL;
}

void clear_exception() {
  error_status = DANU_PYTHON_OK;
}

char *check_exception() {
  if (error_status == DANU_PYTHON_FAIL) {
    return error_message;
  } 
  else {
    return NULL;
  }

}


