// Author          : Nazir_Patel
// Description     : Controller for New Buyer LWC. Saves buyer data and closes 
//                   verification task.

public with sharing class DOANewBuyerController {

    @AuraEnabled
    public static Case getCaseData(String recordId) {
        try {
            Id caseId = resolveCaseId(recordId);
            if (caseId == null) return new Case();

            return [
                SELECT Id, CaseNumber, Type, Name__c, Email__c, Phone__c, Address__c, 
                       National_Identity_Card__c, Is_Dual_Citizen__c, Has_Power_of_Attorney__c, 
                       Amount_Settlement_Type__c, Pending_Amount__c, DOA_Approval_Status__c 
                FROM Case 
                WHERE Id = :caseId 
                LIMIT 1
            ];
        } catch (Exception e) {
            System.debug('Error in getCaseData: ' + e.getMessage());
            throw new AuraHandledException('Error fetching Case details: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static String saveBuyerDetailsAndCloseTask(String recordId, Case caseData) {
        try {
            Id caseId = resolveCaseId(recordId);
            if (caseId == null) {
                throw new AuraHandledException('Unable to locate related Case record.');
            }

            // 1. Reset Approval Status from 'Rejected' to 'Draft' so it can re-enter approval cleanly
            if (caseData.DOA_Approval_Status__c == 'Rejected') {
                caseData.DOA_Approval_Status__c = 'Pending';
            }

            // 2. Update Case with New Buyer Details
            caseData.Id = caseId;
            update caseData;
            System.debug('Case updated successfully ==> ' + caseId);

            // 3. Mark the "Verify & Upload Documents" Task as Closed
            // (Closing this task in the database triggers TaskTrigger -> handleTaskCompletion 
            // to create ONLY the ONE next task: 'Upload Customer Proof...' or 'Confirm Payment'!)
            List<Task> openVerifyTasks = [
                SELECT Id, Status, WhatId 
                FROM Task 
                WHERE WhatId = :caseId 
                  AND Subject LIKE '%Verify & Upload Documents%' 
                  AND Status != 'Closed'
            ];

            for (Task t : openVerifyTasks) {
                t.Status = 'Closed';
                t.Description = 'Documents verified and submitted.';
            }
            if (!openVerifyTasks.isEmpty()) {
                update openVerifyTasks;
                System.debug('Closed Verify Task ==> ' + openVerifyTasks[0].Id);
            }

            return 'SUCCESS';

        } catch (Exception e) {
            System.debug('Error in saveBuyerDetailsAndCloseTask: ' + e.getMessage());
            throw new AuraHandledException(e.getMessage());
        }
    }

    // Helper to resolve Case ID whether launched from Task ('00T') or Case ('500')
    private static Id resolveCaseId(String recordIdStr) {
        if (String.isBlank(recordIdStr)) 
        return null;
        Id recId = (Id) recordIdStr;
        String sObjName = recId.getSObjectType().getDescribe().getName();
        if (sObjName == 'Task') {
            Task t = [SELECT WhatId FROM Task WHERE Id = :recId LIMIT 1];
            return t.WhatId;
        }
        return recId;
    }
}