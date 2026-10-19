trigger ProjectConfigurationTrigger on Project_Configuration__c (before insert, before update, after insert, after undelete) {
    // A record restored from the Recycle Bin is checked too; folders are only created for new configurations
    if (Trigger.isBefore || Trigger.isUndelete) {
        OneRecordPerType.validate(Trigger.new, Trigger.oldMap, Project_Configuration__c.Unit_Type__c, Project_Configuration__c.Project__c,
            'This project already has a {0} configuration. Only one configuration of each unit type is allowed per project.');
    } else if (Trigger.isInsert) {
        ProjectConfigurationFolders.handleAfterInsert(Trigger.newMap);
    }
}