/* *****************************************************
 * P5oqaque events 
 * ***************************************************** */

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

/* *************************************************** */

