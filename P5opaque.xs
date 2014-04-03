#include "EXTERN.h"
#include "perl.h"
#define NO_XSLOCKS
#include "XSUB.h"

#include "xs/P5opaque.c"
#include "xs/P5opaque/slots.c"
#include "xs/P5opaque/events.c"

/* ***************************************************** */

MODULE = P5opaque  PACKAGE = P5opaque

INCLUDE: xs/P5opaque.xs
INCLUDE: xs/P5opaque/slots.xs
INCLUDE: xs/P5opaque/events.xs

