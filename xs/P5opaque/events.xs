MODULE = P5opaque  PACKAGE = P5opaque::events

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

