/* *****************************************************
 * P5oqaque slot accessors
 * ***************************************************** */

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

/* *************************************************** */