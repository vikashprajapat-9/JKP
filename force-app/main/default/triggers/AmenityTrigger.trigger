trigger AmenityTrigger on Amenties__c (before insert, before update, after undelete) {
    // A record restored from the Recycle Bin is checked too
    OneRecordPerType.validate(Trigger.new, Trigger.oldMap, Amenties__c.Type__c, Amenties__c.Project__c,
        'This project already has the {0} amenity. Only one amenity of each type is allowed per project.');
}