public class QCRequestTriggerHandler {
    public static void handleBeforeUpdate(List<QC_Request__c> newRecords,Map<Id, QC_Request__c> oldMap) {
        for (QC_Request__c qc : newRecords) {
            QC_Request__c oldQC = oldMap.get(qc.Id);
            if (qc.Inspection_Engineer__c != null && oldQC.Inspection_Engineer__c == null) {
                qc.QC_Request_Status__c = 'Ready to Inspection';
            }
        }
    }

    public static void handleAfterUpdate( List<QC_Request__c> newRecords, Map<Id, QC_Request__c> oldMap) {
        List<Task> tasksToInsert = new List<Task>();
        for (QC_Request__c qc : newRecords) {
            QC_Request__c oldQC = oldMap.get(qc.Id);
            if (qc.Inspection_Engineer__c != null && oldQC.Inspection_Engineer__c == null) {
                Task t = new Task();
                t.OwnerId = qc.Inspection_Engineer__c;
                t.Subject = 'QC Inspection';
                t.ActivityDate = Date.today().addDays(2);
                t.WhatId = qc.Id;
                t.Description = 'QC inspection is required for the assigned unit.' + '\n QC Request: ' + qc.Name;
                tasksToInsert.add(t);
            }
        }

        if (!tasksToInsert.isEmpty()) {
            insert tasksToInsert;
        }
    }
}