/* Author          : Nazir_Patel
   Description     : Manages ticketing workflow, task creation, approvals, 
                     customer emails, and bell notifications for:
                     1. Deed of Assignment (DOA)
                     2. Addendum (adding a co-purchaser) - No Sub-type
                     3. Other Addendum - Requires Sub_Type__c
*/   
public Without Sharing class CaseDOAHandler {

    // =========================================================================
    // 1. ON CASE CREATION / TYPE UPDATE: Auto-create Task 1
    // =========================================================================
    public static void handleCases(List<Case> newCases) {
        List<Task> taskToInsert = new List<Task>();
        Id csUserId = getUserByRole('Executive Customer Service');
        
        // Prevent duplicate tasks if updating an existing Case
        Set<Id> caseIdsWithExistingTasks = new Set<Id>();
        Set<Id> incomingCaseIds = new Set<Id>();
        for (Case c : newCases) {
            if (c.Id != null) 
                incomingCaseIds.add(c.Id);
        }
        if (!incomingCaseIds.isEmpty()) {
            for (Task t : [SELECT WhatId FROM Task WHERE WhatId IN :incomingCaseIds WITH SYSTEM_MODE]) {
                caseIdsWithExistingTasks.add(t.WhatId);
            }
        }

        for (Case c : newCases) {
            if (c.Id != null && caseIdsWithExistingTasks.contains(c.Id)) {
                continue;
            }

            if (String.isBlank(c.Type)) continue;

            // A. DEED OF ASSIGNMENT
            if (c.Type.equalsIgnoreCase('Deed of Assignment')) {
                Task t = new Task();
                t.Subject      = 'Verify & Upload Documents';
                t.Status       = 'New';
                t.Description  = 'Upload color & clear scanned copies of CDD, NIC/Passport, Risk Profile, AML, and check documents expiry dates.';
                t.Priority     = 'Medium';
                t.ActivityDate = Date.today().addDays(3);
                t.WhatId       = c.Id;
                t.OwnerId      = csUserId;
                taskToInsert.add(t);
            }
            // B. ADDENDUM (ADDING CO-PURCHASER) - NO SUB-TYPE NEEDED
            else if (isCoPurchaserAddendum(c.Type)) {
                Task t = new Task();
                t.Subject      = 'Verify & Upload Documents';
                t.Status       = 'New';
                t.Description  = 'Upload clear scanned copies of:\n' + 
                                 '- Customer Due Diligence Form\n' + 
                                 '- National Identity Card\n' + 
                                 '- Passport (If expired: lost affidavit)\n' + 
                                 '- Customer Risk Profile\n' + 
                                 '- Anti Money Laundering\n' + 
                                 '- If Dual Citizen: Dual Citizenship Certification\n' + 
                                 '- Power of Attorney (if applicable)';
                t.Priority     = 'Medium';
                t.ActivityDate = Date.today().addDays(3);
                t.WhatId       = c.Id;
                t.OwnerId      = csUserId;
                taskToInsert.add(t);
            }
            // C. OTHER ADDENDUM (REQUIRES SUB-TYPE)
            else if (c.Type.equalsIgnoreCase('Other Addendum') && String.isNotBlank(c.Sub_Type__c)) {
                Task t = new Task();
                t.Subject      = 'Verify & Upload Documents for other Addendum';
                t.Status       = 'New';
                t.Description  = 'Upload clear scanned copies of required documents for Addendum: ' + c.Sub_Type__c;
                t.Priority     = 'Medium';
                t.ActivityDate = Date.today().addDays(3);
                t.WhatId       = c.Id;
                t.OwnerId      = csUserId;
                taskToInsert.add(t);
            }
        }
        
        if (!taskToInsert.isEmpty()) {
            insert as system taskToInsert;
            for (Task t : taskToInsert) {
                sendBellNotification('New Task Assigned', 'You have been assigned: ' + t.Subject, t.WhatId, t.OwnerId);
            }
        }
    }

    // Handles updates where Type or Sub-Type was populated on an existing Case
    public static void handleCaseUpdate(List<Case> updatedCases, Map<Id, Case> oldCaseMap) {
        List<Case> casesNeedingTask1 = new List<Case>();
        for (Case c : updatedCases) {
            Case oldC = oldCaseMap != null ? oldCaseMap.get(c.Id) : null;
            if (oldC == null) continue;

            Boolean typeChanged = (c.Type != oldC.Type);

            // 1. Co-purchaser type set
            if (isCoPurchaserAddendum(c.Type) && typeChanged) {
                casesNeedingTask1.add(c);
            }
            // 2. Other Addendum with sub-type set
            else if (c.Type != null && c.Type.equalsIgnoreCase('Other Addendum') && String.isNotBlank(c.Sub_Type__c)) {
                if (typeChanged || String.isBlank(oldC.Sub_Type__c)) {
                    casesNeedingTask1.add(c);
                }
            }
        }
        if (!casesNeedingTask1.isEmpty()) {
            handleCases(casesNeedingTask1);
        }
    }

    // =========================================================================
    // 2. SEQUENTIAL TASK TRANSITIONS
    // =========================================================================
    public static void handleTaskCompletion(List<Task> updatedTasks, Map<Id, Task> oldMap) {
        List<Task> nextTasksToInsert = new List<Task>();
        List<Case> casesToClose      = new List<Case>();
        Set<Id> parentCaseIds        = new Set<Id>();
        Set<Id> casesToFireApproval  = new Set<Id>();

        Id csUserId         = getUserByRole('Executive Customer Service');
        Id legalUserId      = getUserByRole('Head - Legal');
        Id financeUserId    = getUserByRole('Account Executive');
        Id complianceUserId = getUserByRole('Head - Compliance');

        for (Task t : updatedTasks) {
            if (t.WhatId != null && String.valueOf(t.WhatId).startsWith('500')) {
                parentCaseIds.add(t.WhatId);
            }
        }

        if (parentCaseIds.isEmpty()) return;

        Map<Id, Case> caseMap = new Map<Id, Case>([
            SELECT Id, Type, Sub_Type__c, Amount_Settlement_Type__c, DOA_Approval_Status__c, Status 
            FROM Case WHERE Id IN :parentCaseIds
        ]);

        for (Task t : updatedTasks) {
            Task oldTask    = oldMap.get(t.Id);
            Case parentCase = caseMap.get(t.WhatId);

            Boolean wasOpen     = (oldTask.Status != 'Closed' && oldTask.Status != 'Completed' && !oldTask.IsClosed);
            Boolean isNowClosed = (t.Status == 'Closed' || t.Status == 'Completed' || t.IsClosed);

            if (!isNowClosed || !wasOpen || parentCase == null) continue;

            // =================================================================
            // SCENARIO 1: DEED OF ASSIGNMENT
            // =================================================================
            if (parentCase.Type.equalsIgnoreCase('Deed of Assignment')) {

                if (t.Subject != null && t.Subject.contains('Verify & Upload Documents')) {
                    if (parentCase.Amount_Settlement_Type__c == 'Before DOA') {
                        Task finTask        = new Task();
                        finTask.Subject     = 'Confirm Payment';
                        finTask.Status      = 'New';
                        finTask.Priority    = 'High';
                        finTask.ActivityDate = Date.today().addDays(2);
                        finTask.WhatId      = t.WhatId;
                        finTask.OwnerId     = financeUserId;
                        finTask.Description = 'Documents verified. Please confirm payment.';
                        nextTasksToInsert.add(finTask);

                        casesToFireApproval.add(t.WhatId);
                    }
                    else if (parentCase.Amount_Settlement_Type__c == 'On Date DOA') {
                        Task proofTask        = new Task();
                        proofTask.Subject     = 'Upload Customer Proof of Communication for Payment';
                        proofTask.Status      = 'New';
                        proofTask.Priority    = 'Medium';
                        proofTask.ActivityDate = Date.today().addDays(2);
                        proofTask.WhatId      = t.WhatId;
                        proofTask.OwnerId     = csUserId;
                        proofTask.Description = 'Please upload customer communication/proof of payment.';
                        nextTasksToInsert.add(proofTask);
                    }
                }
                else if (t.Subject != null && t.Subject.contains('Upload Customer Proof of Communication for Payment')) {
                    casesToFireApproval.add(t.WhatId);
                }
                else if (t.Subject != null && t.Subject.contains('Confirm / amend DOA')) {
                    Task signingTask        = new Task();
                    signingTask.Subject     = 'Signing';
                    signingTask.Status      = 'New';
                    signingTask.Priority    = 'Medium';
                    signingTask.ActivityDate = Date.today().addDays(3);
                    signingTask.WhatId      = t.WhatId;
                    signingTask.OwnerId     = csUserId;
                    signingTask.Description = 'DOA confirmed by Legal. Please facilitate customer signing.';
                    nextTasksToInsert.add(signingTask);
                }
            }

            // =================================================================
            // SCENARIO 2: ADDENDUM (ADDING CO-PURCHASER) - NO SUB-TYPE
            // =================================================================
            else if (isCoPurchaserAddendum(parentCase.Type)) {

                // Step 1: Verify & Upload Documents Closed -> Create "Confirm Addendum" for Legal + Notify Compliance
                if (t.Subject != null && t.Subject.contains('Verify & Upload Documents')) {
                    Task nextTask        = new Task();
                    nextTask.Subject     = 'Confirm Addendum';
                    nextTask.Status      = 'New';
                    nextTask.Priority    = 'High';
                    nextTask.ActivityDate = Date.today().addDays(2);
                    nextTask.WhatId      = t.WhatId;
                    nextTask.OwnerId     = legalUserId;
                    nextTask.Description = 'Please review documents and confirm Addendum preparation for Adding Co-purchaser.';
                    nextTasksToInsert.add(nextTask);

                    // Notify Compliance Team
                    sendBellNotification('Compliance Alert', 'Documents uploaded for Addendum (adding a co-purchaser). Please review compliance.', t.WhatId, complianceUserId);
                    
                }

                // Step 2: Confirm Addendum Closed -> Create "Signing" for CS
                else if (t.Subject != null && t.Subject.contains('Confirm Addendum')) {
                    Task signingTask        = new Task();
                    signingTask.Subject     = 'Signing';
                    signingTask.Status      = 'New';
                    signingTask.Priority    = 'Medium';
                    signingTask.ActivityDate = Date.today().addDays(3);
                    signingTask.WhatId      = t.WhatId;
                    signingTask.OwnerId     = csUserId;
                    signingTask.Description = 'Addendum confirmed by Legal. Please facilitate customer signing.';
                    nextTasksToInsert.add(signingTask);
                    
                    //NOtify to csutomer over Email
                    sendEmailNotification(new set<Id> {t.whatId});
                }

                // Step 3: Signing Closed -> Auto-update Ticket Status to Closed
                else if (t.Subject != null && t.Subject.contains('Signing')) {
                    casesToClose.add(new Case(Id = parentCase.Id, Status = 'Closed'));
                }
            }

            // =================================================================
            // SCENARIO 3: OTHER ADDENDUM (REQUIRES SUB-TYPE)
            // =================================================================
            else if (parentCase.Type.equalsIgnoreCase('Other Addendum')) {

                if (t.Subject != null && t.Subject.contains('Verify & Upload Documents for other Addendum')) {
                    Task nextTask        = new Task();
                    nextTask.Subject     = 'Confirm Addendum';
                    nextTask.Status      = 'New';
                    nextTask.Priority    = 'High';
                    nextTask.ActivityDate = Date.today().addDays(2);
                    nextTask.WhatId      = t.WhatId;
                    nextTask.OwnerId     = legalUserId;
                    nextTask.Description = 'Please review documents and confirm Addendum preparation for: ' + parentCase.Sub_Type__c;
                    nextTasksToInsert.add(nextTask);

                    // Notify Compliance Team
                    sendBellNotification('Compliance Alert', 'Documents verified for Other Addendum (' + parentCase.Sub_Type__c + ').', t.WhatId, complianceUserId);
                  
                }
                else if (t.Subject != null && t.Subject.contains('Confirm Addendum')) {
                    Task signingTask        = new Task();
                    signingTask.Subject     = 'Signing for other Addendum';
                    signingTask.Status      = 'New';
                    signingTask.Priority    = 'Medium';
                    signingTask.ActivityDate = Date.today().addDays(3);
                    signingTask.WhatId      = t.WhatId;
                    signingTask.OwnerId     = csUserId;
                    signingTask.Description = 'Addendum confirmed by Legal. Please facilitate customer signing for: ' + parentCase.Sub_Type__c;
                    nextTasksToInsert.add(signingTask);
                      // Send Email Notification
                    sendEmailNotification(new set<Id> {t.whatId});
                }
                else if (t.Subject != null && t.Subject.contains('Signing for other Addendum')) {
                    // Notify Finance Team
                    sendBellNotification(
                        'Other Addendum Signing Completed', 
                        'Customer signing completed for Other Addendum (' + parentCase.Sub_Type__c + '). Please take necessary finance actions.', 
                        t.WhatId, 
                        financeUserId
                    );
                   
                }
            }
        }

        // Insert next tasks
        if (!nextTasksToInsert.isEmpty()) {
            insert as system nextTasksToInsert;
            for (Task nt : nextTasksToInsert) {
                sendBellNotification('New Task Assigned', 'You have been assigned: ' + nt.Subject, nt.WhatId, nt.OwnerId);
            }
        }

        // Auto-close Cases if applicable (for Co-purchaser)
        if (!casesToClose.isEmpty()) {
            update as system casesToClose;
        }

        // Fire approval if needed
        if (!casesToFireApproval.isEmpty()) {
            for (Id cId : casesToFireApproval) {
                submitForApproval(cId, 'Payment documents verified. Submitting for Financial Approval.');
            }
        }
    }

    // Helper: Flexible check for Co-purchaser type variations
    private static Boolean isCoPurchaserAddendum(String caseType) {
        if (String.isBlank(caseType)) return false;
        String lower = caseType.toLowerCase();
        return lower.contains('purchaser') && (lower.contains('co') || lower.contains('adding'));
    }

    // =========================================================================
    // 3. APPROVAL STATUS UPDATES (DOA ONLY)
    // =========================================================================
    public static void handleAfterApproval(List<Case> updatedCases, Map<Id, Case> oldCaseMap) {
        Set<Id> approvedCaseIds = new Set<Id>();
        Set<Id> rejectedCaseIds = new Set<Id>();

        for (Case c : updatedCases) {
            Case oldC        = oldCaseMap != null ? oldCaseMap.get(c.Id) : null;
            String oldStatus = oldC != null ? oldC.DOA_Approval_Status__c : '';

            if (c.DOA_Approval_Status__c == 'Approved' && oldStatus != 'Approved') {
                if (c.Type != null && c.Type.equalsIgnoreCase('Deed of Assignment')) {
                    approvedCaseIds.add(c.Id);
                }
            }

            if (c.DOA_Approval_Status__c == 'Rejected' && oldStatus != 'Rejected') {
                if (c.Type != null && c.Type.equalsIgnoreCase('Deed of Assignment')) {
                    rejectedCaseIds.add(c.Id);
                }
            }
        }

        if (!approvedCaseIds.isEmpty()) {
            createLegalTaskForApprovedCases(approvedCaseIds);
        }

        if (!rejectedCaseIds.isEmpty()) {
            handleRejectionAsync(rejectedCaseIds);
        }
    }

    public static void handleSettlementChange(List<Case> newCases, Map<Id, Case> oldCaseMap) {}

    // =========================================================================
    // 4. APPROVED: CREATE LEGAL TASK (DOA)
    // =========================================================================
    private static void createLegalTaskForApprovedCases(Set<Id> caseIds) {
        Id legalUserId = getUserByRole('Head - Legal');
        List<Task> legalTasks = new List<Task>();

        for (Id cId : caseIds) {
            Task t = new Task();
            t.Subject      = 'Confirm / amend DOA';
            t.Status       = 'New';
            t.Priority     = 'High';
            t.ActivityDate = Date.today().addDays(2);
            t.WhatId       = cId;
            t.OwnerId      = legalUserId;
            t.Description  = 'Financial approvals granted. Please confirm or amend the Deed of Assignment.';
            legalTasks.add(t);
        }

        if (!legalTasks.isEmpty()) {
            insert as system legalTasks;
            for (Task t : legalTasks) {
                sendBellNotification('DOA Approved - Action Required', 'Financial approvals completed. Please prepare DOA.', t.WhatId, t.OwnerId);
            }
        }
    }

    // =========================================================================
    // 5. REJECTED: CLEANUP STALE TASKS & RE-OPEN 1 VERIFY TASK (DOA)
    // =========================================================================
    @future
    public static void handleRejectionAsync(Set<Id> rejectedCaseIds) {
        Id csUserId = getUserByRole('Executive Customer Service');

        Map<Id, String> caseToComments = new Map<Id, String>();
        try {
            for (ProcessInstanceStep step : [
                SELECT ProcessInstance.TargetObjectId, Comments, StepStatus, CreatedDate 
                FROM ProcessInstanceStep 
                WHERE ProcessInstance.TargetObjectId IN :rejectedCaseIds 
                  AND StepStatus = 'Rejected' 
                ORDER BY CreatedDate DESC
            ]) {
                Id targetId = step.ProcessInstance.TargetObjectId;
                if (!caseToComments.containsKey(targetId) && String.isNotBlank(step.Comments)) {
                    caseToComments.put(targetId, step.Comments);
                }
            }
        } catch (Exception ex) {
            System.debug('Error fetching rejection comments: ' + ex.getMessage());
        }

        try {
            List<Task> openNonVerifyTasks = [
                SELECT Id, Status, Subject 
                FROM Task 
                WHERE WhatId IN :rejectedCaseIds 
                  AND Status NOT IN ('Closed', 'Completed') 
                  AND (NOT Subject LIKE '%Verify & Upload Documents%')
            ];
            for (Task t : openNonVerifyTasks) {
                t.Status = 'Closed';
            }
            if (!openNonVerifyTasks.isEmpty()) {
                update as system openNonVerifyTasks;
            }
        } catch (Exception ex) {
            System.debug('Error closing stale tasks: ' + ex.getMessage());
        }

        Map<Id, Task> existingVerifyMap = new Map<Id, Task>();
        List<Task> extraVerifyToClose   = new List<Task>();

        for (Task t : [
            SELECT Id, WhatId, Status, Description 
            FROM Task 
            WHERE WhatId IN :rejectedCaseIds 
              AND Subject LIKE '%Verify & Upload Documents%' 
              AND Status NOT IN ('Closed', 'Completed')
        ]) {
            if (!existingVerifyMap.containsKey(t.WhatId)) {
                existingVerifyMap.put(t.WhatId, t);
            } else {
                t.Status = 'Closed';
                extraVerifyToClose.add(t);
            }
        }
        if (!extraVerifyToClose.isEmpty()) {
            update as system extraVerifyToClose;
        }

        List<Task> tasksToInsert = new List<Task>();
        List<Task> tasksToUpdate = new List<Task>();

        for (Id caseId : rejectedCaseIds) {
            String comment = caseToComments.containsKey(caseId) 
                ? caseToComments.get(caseId) 
                : 'No comment provided by approver.';
            
            String descText = 'APPROVAL REJECTED.\nReason / Comments: ' + comment + 
                              '\nPlease re-verify documents, make corrections, and re-submit.';

            if (existingVerifyMap.containsKey(caseId)) {
                Task existing = existingVerifyMap.get(caseId);
                existing.Description = descText;
                existing.Priority    = 'High';
                tasksToUpdate.add(existing);
            } else {
                Task reopenTask        = new Task();
                reopenTask.Subject     = 'Verify & Upload Documents';
                reopenTask.Status      = 'New';
                reopenTask.Priority    = 'High';
                reopenTask.ActivityDate = Date.today().addDays(2);
                reopenTask.WhatId      = caseId;
                reopenTask.OwnerId     = csUserId;
                reopenTask.Description = descText;
                tasksToInsert.add(reopenTask);
            }
        }

        if (!tasksToUpdate.isEmpty()) {
            update as system tasksToUpdate;
        }
        if (!tasksToInsert.isEmpty()) {
            insert as system tasksToInsert;
            for (Task t : tasksToInsert) {
                sendBellNotification(
                    'DOA Approval Rejected', 
                    'Approval rejected. Please review comments and re-upload documents.', 
                    t.WhatId, t.OwnerId
                );
            }
        }
    }

    // =========================================================================
    // 6. HELPER: SUBMIT FOR APPROVAL
    // =========================================================================
    public static void submitForApproval(Id caseId, String comment) {
        try {
            List<ProcessInstance> activeApprovals = [
                SELECT Id FROM ProcessInstance 
                WHERE TargetObjectId = :caseId AND Status = 'Pending' WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (!activeApprovals.isEmpty()) return;

            Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
            req.setComments(comment);
            req.setObjectId(caseId);
            req.setProcessDefinitionNameOrId('DOA_Financial_Dual_Approval');
            Approval.process(req);
        } catch (Exception ex) {
            System.debug('Approval submission notice: ' + ex.getMessage());
        }
    }

    // =========================================================================
    // 7. HELPER: USER LOOKUP BY ROLE
    // =========================================================================
    public static Id getUserByRole(String roleName) {
        List<User> users = [
            SELECT Id FROM User 
            WHERE UserRole.Name = :roleName AND IsActive = true  with SYSTEM_MODE
            LIMIT 1
        ];
        return !users.isEmpty() ? users[0].Id : UserInfo.getUserId();
    }

    // =========================================================================
    // 8. HELPER: BELL NOTIFICATIONS
    // =========================================================================
    public static void sendBellNotification(String title, String body, Id targetId, Id recipientId) {
        try {
            CustomNotificationType notifType = [
                SELECT Id FROM CustomNotificationType 
                WHERE DeveloperName = 'CaseTransferbellnotification' WITH SYSTEM_MODE
                LIMIT 1
            ];
            Messaging.CustomNotification notif = new Messaging.CustomNotification();
            notif.setTitle(title);
            notif.setBody(body);
            notif.setNotificationTypeId(notifType.Id);
            notif.setTargetId(targetId);
            notif.send(new Set<String>{ String.valueOf(recipientId) });
        } catch (Exception ex) {
            System.debug('Notification error: ' + ex.getMessage());
        }
    }
    // Handling Email notification here :: 
    public static void sendEmailNotification(Set<Id> caseId) {
    if (caseId == null || caseId.isEmpty()) return;

    List<Messaging.SingleEmailMessage> emailToSend = new List<Messaging.SingleEmailMessage>();
    List<Case> cases = [SELECT Id, CaseNumber, Type, Sub_Type__c, Name__c, Email__c FROM Case WHERE Id IN :caseId];

    for (Case c : cases) {
        // 1. Skip if customer email is missing
        if (String.isBlank(c.Email__c)) {
            continue;
        }

        // 2. Instantiate a fresh mail object for each Case
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new String[] { c.Email__c });
        mail.setSubject('Your ' + c.Type + ' Document Information (' + c.CaseNumber + ')');
        mail.setSaveAsActivity(true);
        mail.setWhatId(c.Id);

        String customerName = String.isNotBlank(c.Name__c) ? c.Name__c : 'Customer';

        // 3. Clean body with proper spacing
        String body = 'Dear ' + customerName + ',\n\n' 
                    + 'Your ' + c.Type + ' Document for Case ' + c.CaseNumber + ' has been approved by our legal team and is ready for signing.\n\n'
                    + 'Thank you,\n'
                    + 'John Keells Properties\n';

        mail.setPlainTextBody(body);
        emailToSend.add(mail);
    }

    // 4. Send ALL emails in ONE bulk call outside the loop
    if (!emailToSend.isEmpty()) {
        try {
            Messaging.sendEmail(emailToSend);
            System.debug('Customer emails sent successfully: ' + emailToSend.size());
        } catch (Exception e) {
            System.debug('Error sending Customer email: ' + e.getMessage());
        }
    }
}


    // =========================================================================
    // POPULATE OPPORTUNITY BASED ON UNIT (WORKS IN AFTER INSERT / UPDATE)
    // =========================================================================
   
    public static void populateOpportunityFromUnit(List<Case> cases, Map<Id, Case> oldCaseMap) {
        Set<Id> unitIds = new Set<Id>();

        // 1. Collect Unit IDs safely
        for (Case c : cases) {
            Case oldC = oldCaseMap != null ? oldCaseMap.get(c.Id) : null;
            // Only proceed if Unit is populated AND (it's new OR changed)
            if (c.Unit__c != null && (oldC == null || oldC.Unit__c != c.Unit__c)) {
                unitIds.add(c.Unit__c);
            }
        }

        if (unitIds.isEmpty()) return;
		// add filter for stageName
       Set<String> validStages = new Set<String>{
            'SPA Signing',
            'Tranche Payment',
            'Internal QC',
            'External QC',
            'Handover',
            'DLP-Active',
            'DLP-In-Progress'
        };
        
        
        // 2. Query StageName defiened Opportunity for each Unit 
        Map<Id, Id> unitToOppIdMap = new Map<Id, Id>();
        
        for (Opportunity opp : [
            SELECT Id, Unit__c FROM Opportunity 
            WHERE Unit__c IN :unitIds AND StageName IN:validStages WITH SYSTEM_MODE
            
        ]) 
        
        {
            // First time seeing this unit = most recent Opportunity
            if (!unitToOppIdMap.containsKey(opp.Unit__c)) {
                unitToOppIdMap.put(opp.Unit__c, opp.Id);
                system.debug('OPPORUTNITY TAG TO UNIT ====>'+unitToOppIdMap);
            }
        }

        // 3. Only update Cases that actually need the Opportunity tagged
        List<Case> casesToUpdate = new List<Case>();
        for (Case c : cases) {
            if (c.Unit__c != null && unitToOppIdMap.containsKey(c.Unit__c)) {
                Id matchedOppId = unitToOppIdMap.get(c.Unit__c);
                // Prevent duplicate update recursion
                if (c.Opportunity__c != matchedOppId) {
                    casesToUpdate.add(new Case(Id = c.Id,  Opportunity__c = matchedOppId));
                }
            }
        }
        if (!casesToUpdate.isEmpty()) {
            update as system casesToUpdate;
            System.debug('Tagged Opportunity successfully for ' + casesToUpdate.size() + ' Case(s).');
        }
    }
}