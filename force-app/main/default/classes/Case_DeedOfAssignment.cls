/* Author          : Nazir_Patel
   Description     : Dedicated workflow handler for 'Deed of Assignment' (DOA):
                     - Auto-creates Task 1: "Verify & Upload Documents"
                     - Handles settlement branching (Before DOA vs On Date DOA)
                     - Financial Dual Approval submission & re-submission
                     - Rejection loop: cleans stale tasks and reopens 1 fresh Verify task
                     - Approval flow: Legal review task & CS Signing task
                     - Customer email notifications
*/
public without sharing class Case_DeedOfAssignment {
/* 
    // =========================================================================
    // 1. CREATE INITIAL TASK 1: "Verify & Upload Documents"
    // =========================================================================
    public static Task createInitialTask(Case c, Id csUserId) {
        Task t = new Task();
        t.Subject      = 'Verify & Upload Documents';
        t.Status       = 'New';
        t.Description  = 'Upload color & clear scanned copies of CDD, NIC/Passport, Risk Profile, AML, and check documents expiry dates.';
        t.Priority     = 'Medium';
        t.ActivityDate = Date.today().addDays(3);
        t.WhatId       = c.Id;
        t.OwnerId      = csUserId;
        return t;
    }

    // =========================================================================
    // 2. SEQUENTIAL TASK COMPLETION FOR DOA
    // =========================================================================
    public static void handleTaskCompletion(Task t, Case parentCase, List<Task> nextTasksToInsert, Set<Id> casesToFireApproval) {
        Id csUserId      = getUserByRole('Executive Customer Service');
        Id legalUserId   = getUserByRole('Head - Legal');
        Id financeUserId = getUserByRole('Account Executive');

        // Step A: "Verify & Upload Documents" is Completed by CS
        if (t.Subject != null && t.Subject.contains('Verify & Upload Documents')) {
            
            // Branch 1: Before DOA -> Create Confirm Payment + Fire Approval
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
            // Branch 2: On Date DOA -> Create Upload Proof Task for CS
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

        // Step B: "Upload Customer Proof" Completed by CS -> Fire Approval
        else if (t.Subject != null && t.Subject.contains('Upload Customer Proof of Communication for Payment')) {
            casesToFireApproval.add(t.WhatId);
        }

        // Step C: Legal closes "Confirm / amend DOA" -> Create Signing Task & Email Customer
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

            // Notify Customer that document is approved by Legal and ready for signing
            sendCustomerEmail(new Set<Id>{ t.WhatId });
        }
    }

    // =========================================================================
    // 3. DOA APPROVED: CREATE LEGAL TASK
    // =========================================================================
    public static void handleApproved(Set<Id> caseIds) {
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
    // 4. DOA REJECTED: CLEAN STALE TASKS & GUARANTEE ONLY 1 RE-OPENED TASK
    // =========================================================================
    @future
    public static void handleRejectionAsync(Set<Id> rejectedCaseIds) {
        Id csUserId = getUserByRole('Executive Customer Service');

        // 1. Fetch latest rejection comments
        Map<Id, String> caseToComments = new Map<Id, String>();
        try {
            for (ProcessInstanceStep step : [
                SELECT ProcessInstance.TargetObjectId, Comments, StepStatus 
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

        // 2. Close stale non-verify tasks (Confirm Payment, Upload Proof, etc.)
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

        // 3. Ensure strictly ONE open Verify task
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

        // 4. Update existing open task OR Insert EXACTLY ONE new task
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
    // 5. HELPER: SUBMIT FOR FINANCIAL DUAL APPROVAL
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
    // 6. HELPER: USER LOOKUP BY ROLE
    // =========================================================================
    public static Id getUserByRole(String roleName) {
        List<User> users = [
            SELECT Id FROM User 
            WHERE UserRole.Name = :roleName AND IsActive = true WITH SYSTEM_MODE
            LIMIT 1
        ];
        return !users.isEmpty() ? users[0].Id : UserInfo.getUserId();
    }

    // =========================================================================
    // 7. HELPER: BELL NOTIFICATIONS
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

    // =========================================================================
    // 8. HELPER: SEND EMAIL TO CUSTOMER
    // =========================================================================
    public static void sendCustomerEmail(Set<Id> caseIds) {
        if (caseIds == null || caseIds.isEmpty()) return;

        List<Messaging.SingleEmailMessage> emailToSend = new List<Messaging.SingleEmailMessage>();
        List<Case> cases = [
            SELECT Id, CaseNumber, Type, Sub_Type__c, Name__c, Email__c 
            FROM Case 
            WHERE Id IN :caseIds
        ];

        for (Case c : cases) {
            if (String.isBlank(c.Email__c)) continue;

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new String[] { c.Email__c });
            mail.setSubject('Your ' + c.Type + ' Document Information (' + c.CaseNumber + ')');
            mail.setSaveAsActivity(true);
            mail.setWhatId(c.Id);

            String customerName = String.isNotBlank(c.Name__c) ? c.Name__c : 'Customer';
            String body = 'Dear ' + customerName + ',\n\n' 
                        + 'Your ' + c.Type + ' Document for Case ' + c.CaseNumber + ' has been approved by our legal team and is ready for signing.\n\n'
                        + 'Thank you,\n'
                        + 'John Keells Properties\n';

            mail.setPlainTextBody(body);
            emailToSend.add(mail);
        }

        if (!emailToSend.isEmpty()) {
            try {
                Messaging.sendEmail(emailToSend);
            } catch (Exception e) {
                System.debug('Error sending Customer email: ' + e.getMessage());
            }
        }
    } */
}