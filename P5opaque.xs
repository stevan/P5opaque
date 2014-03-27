#include "EXTERN.h"
#include "perl.h"
#define NO_XSLOCKS
#include "XSUB.h"

/* *****************************************************
 * P5oqaque structs and magic vtable
 * ***************************************************** */

typedef struct {
    I32* id;
    HV*  data;
    HV*  callbacks;
} P5opaque;

static int mg_free_instance(pTHX_ SV *sv, MAGIC *mg);
static MGVTBL P5opaque_vtbl = {
    NULL,             /* get */
    NULL,             /* set */
    NULL,             /* len */
    NULL,             /* clear */
    mg_free_instance, /* free */
    NULL,             /* copy */
    NULL,             /* dup */
    NULL              /* local */
};

/* *****************************************************
 * predeclare some internal functions
 * ***************************************************** */

static P5opaque* object_to_instance(SV* object);
static AV* fetch_events_by_name (HV* callbacks, SV* event_name);

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
 * Public functions to be exposed via XS
 * -----------------------------------------------------
 * ***************************************************** */

#define initialize_instance(object) THX_initialize_instance(aTHX_ object)
void THX_initialize_instance(pTHX_ SV* object) {
    assert(object != NULL);
    assert(SvTYPE(object) == SVt_RV); // we only accept references here

    P5opaque* opaque;

    Newx(opaque, 1, P5opaque);
    opaque->id        = new_uuid();
    opaque->data      = newHV();
    opaque->callbacks = newHV();

    sv_magicext(object, newSViv((IV) opaque), PERL_MAGIC_ext, &P5opaque_vtbl, "P5opaque", 0);
}

#define free_instance(instance) THX_free_instance(aTHX_ instance)
void THX_free_instance(pTHX_ SV* instance) {
    assert(instance != NULL);
    assert(SvTYPE(instance) == SVt_IV); // the freed instance is the SV wrapper around the P5opaque pointer

    P5opaque* opaque;

    opaque = (P5opaque*) SvIV(instance);

    //sv_dump(instance);
    //sv_dump((SV*) opaque->data);
    //sv_dump((SV*) opaque->callbacks);

    SvREFCNT_dec(opaque->data);
    SvREFCNT_dec(opaque->callbacks);
    SvREFCNT_dec(instance);

    Safefree(opaque->id);
    opaque->id        = NULL;
    opaque->data      = NULL;
    opaque->callbacks = NULL;

    Safefree(opaque);
    opaque = NULL;
}

#define has_events(object) THX_has_events(aTHX_ object)
SV* THX_has_events(pTHX_ SV* object) {
    P5opaque* opaque = object_to_instance(object);
    return newSViv(HvKEYS(opaque->callbacks));
}

#define bind(object, event_name, callback) THX_bind(aTHX_ object, event_name, callback)
void THX_bind(pTHX_ SV* object, SV* event_name, SV* callback) {
    assert(SvTYPE(callback) == SVt_RV);
    assert(SvTYPE(SvRV(callback)) == SVt_PVCV);

    P5opaque* opaque;
    AV*       events;

    opaque = object_to_instance(object);
    events = fetch_events_by_name(opaque->callbacks, event_name);

    if (events == NULL) {
        events = newAV();
        (void)hv_store_ent(opaque->callbacks, event_name, newRV_noinc((SV*) events), 0);
    }

    av_push(events, SvREFCNT_inc(callback));
}

#define unbind(object, event_name, callback) THX_unbind(aTHX_ object, event_name, callback)
void THX_unbind(pTHX_ SV* object, SV* event_name, SV* callback) {
    assert(SvTYPE(callback) == SVt_RV);
    assert(SvTYPE(SvRV(callback)) == SVt_PVCV);

    P5opaque* opaque;
    AV*       events;

    opaque = object_to_instance(object);
    events = fetch_events_by_name(opaque->callbacks, event_name);

    if (events != NULL) {

        AV* new_events;
        I32 event_array_length, i;

        event_array_length = av_top_index(events);

        if (event_array_length != -1) {
            new_events = newAV();
        }

        for (i = 0; i <= event_array_length; i++) {
            SV* event_cb;

            event_cb = (SV*) *av_fetch(events, i, 0);
            if (SvRV(event_cb) == SvRV(callback)) {
                (void)av_delete(events, i, 0);
            } else {
                av_push(new_events, event_cb);
            }
        }

        if (event_array_length != -1) {
            (void)hv_delete_ent(opaque->callbacks, event_name, G_DISCARD, 0);
            if (av_top_index(new_events) == -1) {
                av_undef(new_events);
            } else {
                (void)hv_store_ent(opaque->callbacks, event_name, newRV_noinc((SV*) new_events), 0);
            }
        }

    }
}

#define fire(object, event_name, args, args_len) THX_fire(aTHX_ object, event_name, args, args_len)
void THX_fire(pTHX_ SV* object, SV* event_name, SV** args, I32 args_len) {
    P5opaque* opaque;
    AV*       events;

    opaque = object_to_instance(object);
    events = fetch_events_by_name(opaque->callbacks, event_name);

    if (events != NULL) {

        I32 event_array_length, i, j;

        event_array_length = av_len(events);

        if (event_array_length != -1) {

            dSP;

            for (i = 0; i <= event_array_length; i++) {
                SV* code;
                code = (SV*) *av_fetch(events, i, 0);

                ENTER;
                SAVETMPS;
                PUSHMARK(SP);
                XPUSHs(object);
                for (j = 0; j <= args_len; j++) {
                    XPUSHs(args[j]);
                }
                PUTBACK;
                (void)call_sv(code, G_VOID|G_DISCARD);
                SPAGAIN;
                FREETMPS;
                LEAVE;
            }
        }
    }
}

/* *****************************************************
 * Private functions ...
 * -----------------------------------------------------
 * ***************************************************** */

// magic destructor ...
static int mg_free_instance(pTHX_ SV *sv, MAGIC *mg) {
    free_instance((SV*) mg->mg_obj);
    return 0;
}

// internal instance accessor
static P5opaque* object_to_instance(SV* object) {
    assert(object != NULL);
    assert(SvTYPE(object) == SVt_PVMG); // once magic is added, the SV is upgraded to PVMG

    if (SvMAGICAL(object)) {
        MAGIC* mg;
        for (mg = SvMAGIC(object); mg; mg = mg->mg_moremagic) {
            if ((mg->mg_type == PERL_MAGIC_ext) && (mg->mg_virtual == &P5opaque_vtbl)) {
                return (P5opaque*) SvIV((SV*) mg->mg_obj);
            }
        }
    }

    croak("not a mop instance");
}

// find/create the events array in the callbacks HV
static AV* fetch_events_by_name (HV* callbacks, SV* event_name) {
    AV* events;

    HE* events_entry = hv_fetch_ent(callbacks, event_name, 0, 0);
    if (events_entry != NULL) {
        events = (AV*) SvRV(HeVAL(events_entry));
        if (SvTYPE(events) != SVt_PVAV) {
            croak("events is not an arrayref");
        }
        return events;
    } else {
        return NULL;
    }
}

/* ***************************************************** */

MODULE = P5opaque		PACKAGE = P5opaque

void
initialize_instance(object)
    SV* object;

SV*
has_events(object)
    SV* object;

void
bind(object, event_name, callback)
    SV *object
    SV *event_name
    SV *callback
    CODE:
        bind(object, event_name, callback);
        XSRETURN(1);

void
unbind(object, event_name, callback)
    SV *object
    SV *event_name
    SV *callback
    CODE:
        unbind(object, event_name, callback);
        XSRETURN(1);

void
fire(object, event_name, ...)
    SV* object
    SV* event_name
    PREINIT:
        I32 j;
        SV** args;
    CODE:
        Newx(args, items, SV*);
        for (j = 0; j <= items; j++) {
            args[j] = ST(j);
        }
        fire(object, event_name, args, items);
        Safefree(args);
        XSRETURN(1);


