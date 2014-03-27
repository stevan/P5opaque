#include "EXTERN.h"
#include "perl.h"
#define NO_XSLOCKS
#include "XSUB.h"

/* *****************************************************
 * P5oqaque structs and magic vtable
 * ***************************************************** */

typedef struct {
    SV* id;
    HV* data;
    HV* callbacks;
} P5opaque;

static MGVTBL P5opaque_vtbl = {
    NULL, /* get */
    NULL, /* set */
    NULL, /* len */
    NULL, /* clear */
    NULL, /* free */
    NULL, /* copy */
    NULL, /* dup */
    NULL  /* local */
};

/* *****************************************************
 * Quick simple (and wrong) UUID mechanism, this will
 * get replaced, but sufficient for now,
 * ***************************************************** */

/* XXX replace this with a real implementation */
static I32* new_uuid() {
    I32* uuid;
    int i;

    Newx(uuid, 4, I32);

    if (!PL_srand_called) {
        (void)seedDrand01((Rand_seed_t)Perl_seed(aTHX));
        PL_srand_called = TRUE;
    }

    for (i = 0; i < 4; ++i) {
        /* XXX this is terrible */
        uuid[i] = (I32)(Drand01() * (double)(2<<30));
    }

    return uuid;
}

/* *****************************************************
 * functions ...
 * ***************************************************** */

#define initialize_instance(object) THX_initialize_instance(aTHX_ object)
void THX_initialize_instance(pTHX_ SV* object) {

    assert(object != NULL);
    assert(SvRV(object));

    P5opaque* opaque;
    SV*       opaque_sv;

    opaque = Newx(opaque, 1, P5opaque);
    opaque->id        = newSViv(*new_uuid());
    opaque->data      = newHV();
    opaque->callbacks = newHV();

    SvREFCNT_inc(opaque->id);
    SvREFCNT_inc(opaque->data);
    SvREFCNT_inc(opaque->callbacks);

    opaque_sv = newSViv((I32) opaque);

    sv_magicext(object, opaque_sv, PERL_MAGIC_ext, &P5opaque_vtbl, "P5opaque", 0);

    sv_dump(object);
    sv_dump(opaque_sv);
}

MODULE = P5opaque		PACKAGE = P5opaque

void
initialize_instance(object)
    SV* object;














