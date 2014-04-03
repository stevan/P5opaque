#include "EXTERN.h"
#include "perl.h"
#define NO_XSLOCKS
#include "XSUB.h"

/* *****************************************************
 * P5oqaque MopIV structs and magic vtable
 * ***************************************************** */

typedef struct {
    I32* id;
    HV*  slots;
    HV*  callbacks;
} MopIV;

static int mg_freeMopIV(pTHX_ SV *sv, MAGIC *mg);
static MGVTBL MopIV_vtbl = {
    NULL,         /* get   */
    NULL,         /* set   */
    NULL,         /* len   */
    NULL,         /* clear */
    mg_freeMopIV, /* free  */
    NULL,         /* copy  */
    NULL,         /* dup   */
    NULL          /* local */
};

/* *****************************************************
 * predeclare some internal functions
 * ***************************************************** */

static MopIV* SV_to_MopIV(SV* object);
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

#define newMopIVrv(object) THX_newMopIVrv(aTHX_ object)
void THX_newMopIVrv(pTHX_ SV* object) {
    assert(object != NULL);

    if (SvTYPE(object) != SVt_RV) {
        croak("object is not a reference");
    }

    MopIV* opaque;

    Newx(opaque, 1, MopIV);
    opaque->id        = new_uuid();
    opaque->slots     = newHV();
    opaque->callbacks = newHV();

    sv_magicext(SvRV(object), NULL, PERL_MAGIC_ext, &MopIV_vtbl, (char*) opaque, 0);
}

#define newMopIV() THX_newMopIV(aTHX)
SV* THX_newMopIV(pTHX) {
    SV* object = newRV_noinc(newSV(0));
    newMopIVrv(object);
    return object;
}

#define newMopIVhv() THX_newMopIVhv(aTHX)
SV* THX_newMopIVhv(pTHX) {
    SV* object = newRV_noinc((SV*) newHV());
    newMopIVrv(object);
    return object;
}

#define newMopIVav() THX_newMopIVav(aTHX)
SV* THX_newMopIVav(pTHX) {
    SV* object = newRV_noinc((SV*) newAV());
    newMopIVrv(object);
    return object;
}

#define freeMopIV(opaque) THX_freeMopIV(aTHX_ opaque)
void THX_freeMopIV(pTHX_ MopIV* opaque) {
    assert(opaque != NULL);

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
    MopIV* opaque     = SV_to_MopIV(object);
    HE* slot_entry = hv_fetch_ent(opaque->slots, slot_name, 0, 0);
    return slot_entry == NULL ? newSV(0) : HeVAL(slot_entry);
}

#define set_at_slot(object, slot_name, slot_value) THX_set_at_slot(aTHX_ object, slot_name, slot_value)
void THX_set_at_slot(pTHX_ SV* object, SV* slot_name, SV* slot_value) {
    MopIV* opaque = SV_to_MopIV(object);
    SvREFCNT_inc(slot_value);
    (void)hv_store_ent(opaque->slots, slot_name, slot_value, 0);
}

#define has_at_slot(object, slot_name) THX_has_at_slot(aTHX_ object, slot_name)
bool THX_has_at_slot(pTHX_ SV* object, SV* slot_name) {
    MopIV* opaque = SV_to_MopIV(object);
    return hv_exists_ent(opaque->slots, slot_name, 0);
}

// Events ...

#define has_events(object) THX_has_events(aTHX_ object)
SV* THX_has_events(pTHX_ SV* object) {
    MopIV* opaque = SV_to_MopIV(object);
    return newSViv(HvKEYS(opaque->callbacks));
}

#define bind_event(object, event_name, callback) THX_bind_event(aTHX_ object, event_name, callback)
void THX_bind_event(pTHX_ SV* object, SV* event_name, SV* callback) {

    if (SvTYPE(callback) != SVt_RV || SvTYPE(SvRV(callback)) != SVt_PVCV) {
        croak("callback is not a CODE reference");
    }

    MopIV* opaque;
    AV* events;

    opaque = SV_to_MopIV(object);
    events = fetch_events_by_name(opaque->callbacks, event_name);

    if (events == NULL) {
        events = newAV();
        (void)hv_store_ent(opaque->callbacks, event_name, newRV_noinc((SV*) events), 0);
    }

    av_push(events, SvREFCNT_inc(callback));
}

#define unbind_event(object, event_name, callback) THX_unbind_event(aTHX_ object, event_name, callback)
void THX_unbind_event(pTHX_ SV* object, SV* event_name, SV* callback) {

    if (SvTYPE(callback) != SVt_RV || SvTYPE(SvRV(callback)) != SVt_PVCV) {
        croak("callback is not a CODE reference");
    }

    MopIV* opaque;
    AV* events;

    opaque = SV_to_MopIV(object);
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
    MopIV* opaque;
    AV* events;

    opaque = SV_to_MopIV(object);
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
static int mg_freeMopIV(pTHX_ SV *sv, MAGIC *mg) {
    if (SvREFCNT(sv) == 0) {
        freeMopIV((MopIV*) mg->mg_ptr);
        mg->mg_ptr = NULL;
    }
    return 0;
}

// internal instance accessor
static MopIV* SV_to_MopIV(SV* object) {
    assert(object != NULL);

    if (SvTYPE(object) != SVt_RV || SvTYPE(SvRV(object)) != SVt_PVMG) {
        croak("object is not a magic reference");
    }

    if (SvMAGICAL(SvRV(object))) {
        MAGIC* mg;
        for (mg = SvMAGIC(SvRV(object)); mg; mg = mg->mg_moremagic) {
            if ((mg->mg_type == PERL_MAGIC_ext) && (mg->mg_virtual == &MopIV_vtbl)) {
                return (MopIV*) mg->mg_ptr;
            }
        }
    }

    croak("object is not a mop instance");
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
newMopIVrv(object)
    SV* object;

SV*
newMopIV();

SV*
newMopIVhv();

SV*
newMopIVav();

MODULE = P5opaque       PACKAGE = P5opaque::slots

void
get(object, slot_name)
    SV* object;
    SV* slot_name;
    PPCODE:
        EXTEND(SP, 1);
        PUSHs(get_at_slot(object, slot_name));

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


