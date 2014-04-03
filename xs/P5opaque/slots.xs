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
