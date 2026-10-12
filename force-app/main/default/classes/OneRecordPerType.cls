// Allows one record per Type: one Portal Info record per portal, and one amenity and one configuration of each type
// per project. Runs without sharing, so records the user cannot see still count.
public without sharing class OneRecordPerType {

    // Adds an error on the type field of every record whose type is already taken, by a saved record or by an
    // earlier record in the same save, within the same parent (or in the whole object when parentField is null).
    // "{0}" in the message becomes the type's label. Records without a type (or without a parent) are not checked,
    // and on update only records whose type or parent changed are, so older records can still be edited.
    public static void validate(List<SObject> records, Map<Id, SObject> oldById, Schema.SObjectField typeField,
            Schema.SObjectField parentField, String message) {
        String typeName = String.valueOf(typeField);
        List<Integer> changed = new List<Integer>();
        Set<String> types = new Set<String>();
        Set<Id> parents = new Set<Id>();
        Set<Id> saving = new Set<Id>();
        for (Integer i = 0; i < records.size(); i++) {
            SObject record = records[i];
            if (record.Id != null) {
                saving.add(record.Id);
            }
            if (!isChecked(record, typeField, parentField)) {
                continue;
            }
            types.add((String) record.get(typeField));
            if (parentField != null) {
                parents.add((Id) record.get(parentField));
            }
            SObject old = oldById == null ? null : oldById.get(record.Id);
            if (old == null || key(old, typeField, parentField) != key(record, typeField, parentField)) {
                changed.add(i);
            }
        }
        if (changed.isEmpty()) {
            return;
        }

        // Types in use: saved records outside this save, and the records in this save that keep their type
        Set<String> taken = new Set<String>();
        String soql = 'SELECT ' + typeName + (parentField == null ? '' : ', ' + parentField)
            + ' FROM ' + records[0].getSObjectType()
            + ' WHERE ' + typeName + ' IN :types AND Id NOT IN :saving'
            + (parentField == null ? '' : ' AND ' + parentField + ' IN :parents');
        Map<String, Object> binds = new Map<String, Object>{ 'types' => types, 'saving' => saving, 'parents' => parents };
        for (SObject existing : Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE)) {
            taken.add(key(existing, typeField, parentField));
        }
        Set<Integer> changedIndexes = new Set<Integer>(changed);
        for (Integer i = 0; i < records.size(); i++) {
            if (!changedIndexes.contains(i) && isChecked(records[i], typeField, parentField)) {
                taken.add(key(records[i], typeField, parentField));
            }
        }

        Map<String, String> labels = new Map<String, String>();
        for (Schema.PicklistEntry entry : typeField.getDescribe().getPicklistValues()) {
            labels.put(entry.getValue().toLowerCase(), entry.getLabel());
        }
        for (Integer i : changed) {
            SObject record = records[i];
            String recordKey = key(record, typeField, parentField);
            if (taken.contains(recordKey)) {
                String type = (String) record.get(typeField);
                String label = labels.containsKey(type.toLowerCase()) ? labels.get(type.toLowerCase()) : type;
                record.addError(typeName, message.replace('{0}', label));
            } else {
                // The first record in the save gets the type; later ones with the same type are refused
                taken.add(recordKey);
            }
        }
    }

    // Records without a type, or without a parent when there is one, are not limited
    private static Boolean isChecked(SObject record, Schema.SObjectField typeField, Schema.SObjectField parentField) {
        return String.isNotBlank((String) record.get(typeField)) && (parentField == null || record.get(parentField) != null);
    }

    private static String key(SObject record, Schema.SObjectField typeField, Schema.SObjectField parentField) {
        String type = (String) record.get(typeField);
        String parent = parentField == null ? '' : String.valueOf(record.get(parentField));
        return parent + '|' + (type == null ? '' : type.toLowerCase());
    }
}