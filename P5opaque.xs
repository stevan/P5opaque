#include "EXTERN.h"
#include "perl.h"
#define NO_XSLOCKS
#include "XSUB.h"

/* *****************************************************
 * P5oqaque OV structs and magic vtable
 * ***************************************************** */

typedef struct {
    I32* id;
    HV*  slots;
    HV*  callbacks;
} OV;

static int mg_free_OV(pTHX_ SV *sv, MAGIC *mg);
static MGVTBL OV_vtbl = {
    NULL,       /* get */
    NULL,       /* set */
    NULL,       /* len */
    NULL,       /* clear */
    mg_free_OV, /* free */
    NULL,       /* copy */
    NULL,       /* dup */
    NULL        /* local */
};

/* *****************************************************
 * predeclare some internal functions
 * ***************************************************** */

static OV* SV_to_OV(SV* object);
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

#define newOV() THX_newOV(aTHX)
SV* THX_newOV(pTHX) {
    SV* object;
    OV* opaque;

    object = newRV_noinc(newSV(0));

    Newx(opaque, 1, OV);
    opaque->id        = new_uuid();
    opaque->slots     = newHV();
    opaque->callbacks = newHV();

    sv_magicext(SvRV(object), NULL, PERL_MAGIC_ext, &OV_vtbl, (char*) opaque, 0);

    return object;
}

#define newOVrv(object) THX_newOVrv(aTHX_ object)
void THX_newOVrv(pTHX_ SV* object) {
    assert(object != NULL);
    assert(SvTYPE(object) == SVt_RV); // we only accept references here

    OV* opaque;

    Newx(opaque, 1, OV);
    opaque->id        = new_uuid();
    opaque->slots     = newHV();
    opaque->callbacks = newHV();

    sv_magicext(SvRV(object), NULL, PERL_MAGIC_ext, &OV_vtbl, (char*) opaque, 0);
}

#define freeOV(opaque) THX_freeOV(aTHX_ opaque)
void THX_freeOV(pTHX_ OV* opaque) {
    assert(opaque != NULL);

    warn("HEY FOLKS!");

    hv_undef(opaque->slots);
    hv_undef(opaque->callbacks);

    Safefree(opaque->id);
    opaque->id        = NULL;
    opaque->slots     = NULL;
    opaque->callbacks = NULL;

    Safefree(opaque);
    opaque = NULL;
}

// Slot access ...

#define get_at_slot(object, slot_name) THX_get_at_slot(aTHX_ object, slot_name)
SV* THX_get_at_slot(pTHX_ SV* object, SV* slot_name) {
    OV* opaque     = SV_to_OV(object);
    HE* slot_entry = hv_fetch_ent(opaque->slots, slot_name, 0, 0);
    fprintf(stderr, ">> GET XS\n");
    sv_dump(HeVAL(slot_entry));
    fprintf(stderr, "<< GET XS\n");
    return slot_entry == NULL ? newSV(0) : HeVAL(slot_entry);
}

#define set_at_slot(object, slot_name, slot_value) THX_set_at_slot(aTHX_ object, slot_name, slot_value)
void THX_set_at_slot(pTHX_ SV* object, SV* slot_name, SV* slot_value) {
    OV* opaque = SV_to_OV(object);
    SvREFCNT_inc(slot_value);
    (void)hv_store_ent(opaque->slots, slot_name, slot_value, 0);
    fprintf(stderr, ">> SET XS\n");
    sv_dump(slot_value);
    fprintf(stderr, "<< SET XS\n");
}

#define has_at_slot(object, slot_name) THX_has_at_slot(aTHX_ object, slot_name)
bool THX_has_at_slot(pTHX_ SV* object, SV* slot_name) {
    OV* opaque = SV_to_OV(object);
    return hv_exists_ent(opaque->slots, slot_name, 0);
}

// Events ...

#define has_events(object) THX_has_events(aTHX_ object)
SV* THX_has_events(pTHX_ SV* object) {
    OV* opaque = SV_to_OV(object);
    return newSViv(HvKEYS(opaque->callbacks));
}

#define bind_event(object, event_name, callback) THX_bind_event(aTHX_ object, event_name, callback)
void THX_bind_event(pTHX_ SV* object, SV* event_name, SV* callback) {
    assert(SvTYPE(callback) == SVt_RV);
    assert(SvTYPE(SvRV(callback)) == SVt_PVCV);

    OV* opaque;
    AV* events;

    opaque = SV_to_OV(object);
    events = fetch_events_by_name(opaque->callbacks, event_name);

    if (events == NULL) {
        events = newAV();
        (void)hv_store_ent(opaque->callbacks, event_name, newRV_noinc((SV*) events), 0);
    }

    av_push(events, SvREFCNT_inc(callback));
}

#define unbind_event(object, event_name, callback) THX_unbind_event(aTHX_ object, event_name, callback)
void THX_unbind_event(pTHX_ SV* object, SV* event_name, SV* callback) {
    assert(SvTYPE(callback) == SVt_RV);
    assert(SvTYPE(SvRV(callback)) == SVt_PVCV);

    OV* opaque;
    AV* events;

    opaque = SV_to_OV(object);
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

#define fire_event(object, event_name, args, args_len) THX_fire_event(aTHX_ object, event_name, args, args_len)
void THX_fire_event(pTHX_ SV* object, SV* event_name, SV** args, I32 args_len) {
    OV* opaque;
    AV* events;

    opaque = SV_to_OV(object);
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
static int mg_free_OV(pTHX_ SV *sv, MAGIC *mg) {
    if (SvREFCNT(sv) == 0) {
        freeOV((OV*) mg->mg_ptr);
        mg->mg_ptr = NULL;
    }
    return 0;
}

// internal instance accessor
static OV* SV_to_OV(SV* object) {
    assert(object != NULL);
    assert(SvTYPE(object) == SVt_RV);         // the base type is a reference ...
    assert(SvTYPE(SvRV(object)) == SVt_PVMG); // once magic is added, the underlying SV is upgraded to PVMG

    if (SvMAGICAL(SvRV(object))) {
        MAGIC* mg;
        for (mg = SvMAGIC(SvRV(object)); mg; mg = mg->mg_moremagic) {
            if ((mg->mg_type == PERL_MAGIC_ext) && (mg->mg_virtual == &OV_vtbl)) {
                return (OV*) mg->mg_ptr;
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

SV*
newOV();

void
newOVrv(object)
    SV* object;

MODULE = P5opaque       PACKAGE = P5opaque::slots

SV*
get(object, slot_name)
    SV* object;
    SV* slot_name;
    CODE:
        RETVAL = get_at_slot(object, slot_name);
    OUTPUT:
        RETVAL

void
set(object, slot_name, slot_value)
    SV* object;
    SV* slot_name;
    SV* slot_value;
    CODE:
        set_at_slot(object, slot_name, slot_value);
        XSRETURN(2);

SV*
has(object, slot_name)
    SV* object;
    SV* slot_name;
    CODE:
        RETVAL = boolSV(has_at_slot(object, slot_name));
    OUTPUT:
        RETVAL

MODULE = P5opaque       PACKAGE = P5opaque::events

SV*
has_events(object)
    SV* object;

void
bind(object, event_name, callback)
    SV *object
    SV *event_name
    SV *callback
    CODE:
        bind_event(object, event_name, callback);
        XSRETURN(1);

void
unbind(object, event_name, callback)
    SV *object
    SV *event_name
    SV *callback
    CODE:
        unbind_event(object, event_name, callback);
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
        fire_event(object, event_name, args, items);
        Safefree(args);
        XSRETURN(1);


