trigger PortalInfoTrigger on Portal_Info__c (before insert, before update, after undelete) {
    // One record per portal (Customer, Channel partner); a record restored from the Recycle Bin is checked too
    OneRecordPerType.validate(Trigger.new, Trigger.oldMap, Portal_Info__c.Type__c, null,
        'Only one Portal Info record is allowed for {0}. Update the existing record instead.');
}