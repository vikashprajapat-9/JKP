public class TaskTriggerHandler {

    public static void handleAfter(List<Task> newTasks,Map<Id, Task> oldTaskMap,Boolean isInsert,Boolean isUpdate) {
        updateOpportunityStage(newTasks, oldTaskMap);
    }

    private static void updateOpportunityStage(List<Task> newTasks,Map<Id, Task> oldTaskMap ) {
        Set<Id> opportunityIds = new Set<Id>();
        for (Task task : newTasks) {
            if (task.Subject != 'SPA Signing & Upload') {
                continue;
            }
            if (task.Status != 'Completed') {
                continue;
            }
            if (oldTaskMap != null) {
                Task oldTask = oldTaskMap.get(task.Id);
                if (oldTask != null && oldTask.Status == 'Completed') {
                    continue;
                }
            }
            if (task.WhatId == null) {
                continue;
            }
            if (String.valueOf(task.WhatId).startsWith('006')) {
                opportunityIds.add(task.WhatId);
            }
        }
        if (opportunityIds.isEmpty()) {
            return;
        }

        List<Opportunity> opportunitiesToUpdate =new List<Opportunity>();
        for (Opportunity opp : [SELECT Id, StageName, Unit__c, Unit__r.Internal_QC__c FROM Opportunity WHERE Id IN :opportunityIds
        ]) {
            if (opp.StageName != 'SPA Signing') {
                continue;
            }
            if (opp.Unit__c != null && opp.Unit__r.Internal_QC__c == true) {
                opp.StageName = 'Internal QC';

            } else {
                opp.StageName = 'Tranche Payment';
            }
            opportunitiesToUpdate.add(opp);
        }
        if (!opportunitiesToUpdate.isEmpty()) {
            update opportunitiesToUpdate;
        }
    }
}