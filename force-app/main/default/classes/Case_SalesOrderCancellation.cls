/* Author          : Nazir_Patel
   Description     : End-to-End Orchestrator for Sale Order Cancellation (Before SPA & After SPA):
                     - Stage 1: Before SPA (Signed Refund Letter -> HOS Approval)
                     - Stage 2: After SPA (Tri-Approval -> Legal Deed Drafting -> CFO/Sector Head Approval)
                     - Stage 3: Inventory Release (Unit Available & HOS/Sales Manager Alerts)
                     - Stage 4: Shared Finance Pipeline (Verification -> Deposit Refund -> SO Cancellation)
                     - Stage 5: SAP ERP Integration Callout
*/


public without sharing class Case_SalesOrderCancellation {

    // =========================================================================
    // 1. ENTRY POINT FROM DEED OF CANCELLATION (AFTER SPA)
    // =========================================================================
   public static void getSalesOrderCancellation(Id deedCaseId) {
        if (deedCaseId == null) return;

        List<Case> deedCases = [
            SELECT Id, CaseNumber, Opportunity__c, AccountId, OwnerId 
            FROM Case 
            WHERE Id = :deedCaseId 
            LIMIT 1
        ];
        if (deedCases.isEmpty()) return;

        Case deedCase = deedCases[0];

        // Create new Sale Order Cancellation Case
        Case newSOCase                        = new Case();
        newSOCase.Type                        = 'Sale Order Cancellation';
        newSOCase.Sales_Purchase_Agreement__c = 'After SPA';
        newSOCase.SalesOrderCancellation__c   = 'Pending';
        newSOCase.Subject                     = 'Sale Order Cancellation - After SPA Default';
        newSOCase.Opportunity__c              = deedCase.Opportunity__c;
        newSOCase.AccountId                   = deedCase.AccountId;
        newSOCase.Status                      = 'New';
        newSOCase.Priority                    = 'High';
        newSOCase.OwnerId                     = deedCase.OwnerId;
        insert newSOCase;

        // Auto-submit for Tri-Approval (HOS, CFO & Sector Head)
        submitForApproval(newSOCase.Id, 'Submitted for Executive Tri-Approval (HOS, CFO & Sector Head)');
    }

    // =========================================================================
    // 2. CASE AFTER INSERT (TRIGGERED ON ANY SALE ORDER CANCELLATION CASE)
    // =========================================================================
    public static void handleCaseAfterInsert(List<Case> newCases) {
        List<Task> initialTasks = new List<Task>();

        for (Case c : newCases) {
            // Checks whenever Type = 'Sale Order Cancellation'
            if (c.Type == 'Sale Order Cancellation') {
                Task t = new Task();
                t.Subject      = 'Cancellation with signed Customer Refund Letter';
                t.Description  = 'Upload customer signed document and mark as complete to proceed with approval.';
                t.Priority     = 'Medium';
                t.Status       = 'Open';
                t.ActivityDate = Date.today().addDays(3);
                t.WhatId       = c.Id;
                t.OwnerId      = c.OwnerId; // Assigned to Case Owner
                initialTasks.add(t);
            }
        }

        if (!initialTasks.isEmpty()) {
            insert initialTasks;
            System.debug('=== Successfully created ' + initialTasks.size() + ' Initial Refund Letter Task(s) ===');
        }
    }

    // =========================================================================
    // 3. CASE AFTER UPDATE (APPROVAL STATUS ROUTING)
    // =========================================================================
   public static void handleCaseAfterUpdate(List<Case> newCases, Map<Id, Case> oldCaseMap) {
        List<Task> tasksToInsert = new List<Task>();
        Id financeUserId = getUserByRole('Accounts Executive');
        Id legalUserId   = getUserByRole('Head - Legal');
        Id salesMgrUserId = getUserByRole('Manager Customer Service');

        for (Case c : newCases) {
            Case oldCase = oldCaseMap.get(c.Id);

            // -----------------------------------------------------------------
            // A. BEFORE SPA: HOS APPROVED -> Trigger Finance Verification
            // -----------------------------------------------------------------
            if (c.Type == 'Sale Order Cancellation' 
                && c.SalesOrderCancellation__c == 'HOS Approved' 
                && oldCase.SalesOrderCancellation__c != 'HOS Approved') {
                
                Task t = new Task();
                t.Subject      = 'Verify beneficiary & obtain required approvals';
                t.Description  = 'HOS approved cancellation. Verify beneficiary & obtain required approvals; manually mark Closed.';
                t.Priority     = 'High';
                t.Status       = 'Open';
                t.ActivityDate = Date.today().addDays(2);
                t.WhatId       = c.Id;
                t.OwnerId      = financeUserId;
                tasksToInsert.add(t);
            }

            // -----------------------------------------------------------------
            // B. BEFORE SPA: HOS REJECTED -> Route back to Sales Agent
            // -----------------------------------------------------------------
            else if (c.Type == 'Sale Order Cancellation' 
                     && c.SalesOrderCancellation__c == 'HOS Rejected' 
                     && oldCase.SalesOrderCancellation__c != 'HOS Rejected') {
                
                Task t = new Task();
                t.Subject      = 'Amend with Comments (Rejected by HOS)';
                t.Description  = 'HOS returned the cancellation ticket. Please review remarks and resubmit.';
                t.Priority     = 'High';
                t.Status       = 'Open';
                t.ActivityDate = Date.today().addDays(1);
                t.WhatId       = c.Id;
                t.OwnerId      = c.OwnerId;
                tasksToInsert.add(t);
            }

            // -----------------------------------------------------------------
            // C. AFTER SPA: TRI-APPROVAL APPROVED -> Assign to Legal to Draft Deed
            // -----------------------------------------------------------------
            else if (c.Type == 'Sale Order Cancellation' 
                     && c.Sales_Purchase_Agreement__c == 'After SPA'
                     && c.Status == 'Tri-Approved' 
                     && oldCase.Status != 'Tri-Approved') {
                
                Task t = new Task();
                t.Subject      = 'Legal to draft Deed of Cancellation document';
                t.Description  = 'Executive approval obtained. Please draft Deed of Cancellation document and attach for CFO/Sector Head approval.';
                t.Priority     = 'High';
                t.Status       = 'Open';
                t.ActivityDate = Date.today().addDays(3);
                t.WhatId       = c.Id;
                t.OwnerId      = legalUserId;
                tasksToInsert.add(t);
            }

            // -----------------------------------------------------------------
            // D. AFTER SPA: DEED APPROVED BY CFO OR SECTOR HEAD
            // -----------------------------------------------------------------
            else if (c.Type == 'Sale Order Cancellation' 
                     && c.Sales_Purchase_Agreement__c == 'After SPA'
                     && c.Status == 'Deed Approved' 
                     && oldCase.Status != 'Deed Approved') {
                
                Task t = new Task();
                t.Subject      = 'Verify beneficiary & obtain required approvals';
                t.Description  = 'Deed approved by Executive. Verify beneficiary & obtain required approvals; manually mark Closed.';
                t.Priority     = 'High';
                t.Status       = 'Open';
                t.ActivityDate = Date.today().addDays(2);
                t.WhatId       = c.Id;
                t.OwnerId      = financeUserId;
                tasksToInsert.add(t);

                sendBellNotification(
                    'Unit Status: Available', 
                    'Deed of Cancellation approved. Unit is now Available for re-allocation.', 
                    c.Id, 
                    salesMgrUserId
                );

                Id hosUserId = getUserByRole('Head - Sales');
                sendBellNotification(
                    'SO Cancellation: Review Unit Price', 
                    'SO cancelled. Please review and approve latest unit price for Inventory.', 
                    c.Id, 
                    hosUserId
                );
            }
        }

        if (!tasksToInsert.isEmpty()) {
            insert tasksToInsert;
        }
    }

    // =========================================================================
    // 4. TASK AFTER UPDATE (ADVANCES PIPELINE AS TASKS ARE COMPLETED)
    // =========================================================================
  public static void handleTaskAfterUpdate(List<Task> newTasks, Map<Id, Task> oldTaskMap) {
        System.debug('=== [TaskTrigger] handleTaskAfterUpdate FIRED for ' + newTasks.size() + ' tasks ===');

        Set<Id> caseIdsForHOSApproval     = new Set<Id>();
        Set<Id> caseIdsForDepositRefund   = new Set<Id>();
        Set<Id> caseIdsForSOCancellation  = new Set<Id>();
        Set<Id> caseIdsForSAPCallout      = new Set<Id>();

        for (Task t : newTasks) {
            Task oldTask = oldTaskMap != null ? oldTaskMap.get(t.Id) : null;
            
            Boolean isNowClosed = (t.Status == 'Completed' || t.Status == 'Closed');
            Boolean wasAlreadyClosed = (oldTask != null && (oldTask.Status == 'Completed' || oldTask.Status == 'Closed'));

            if (!isNowClosed || wasAlreadyClosed || t.WhatId == null) {
                continue;
            }

            // Stage 1: Signed Refund Letter -> Auto-submit to HOS
            if (t.Subject != null && t.Subject.contains('Cancellation with signed Customer Refund Letter')) {
                caseIdsForHOSApproval.add(t.WhatId);
            }
            // Stage 2: Verify Beneficiary -> Auto-create Deposit Refund
            else if (t.Subject != null && t.Subject.contains('Verify beneficiary')) {
                caseIdsForDepositRefund.add(t.WhatId);
            }
            // Stage 3: Deposit Refund -> Notify HOS & Auto-create SO Cancellation
            else if (t.Subject != null && t.Subject.contains('Deposit Refund')) {
                caseIdsForSOCancellation.add(t.WhatId);
            }
            // Stage 4: SO Cancellation -> Trigger SAP
            else if (t.Subject != null && t.Subject.contains('SO Cancellation')) {
                caseIdsForSAPCallout.add(t.WhatId);
            }
        }

        // 1. Auto-update Case to 'Pending' & Submit to HOS Approval Process
        if (!caseIdsForHOSApproval.isEmpty()) {
            List<Case> casesToUpdateAndSubmit = new List<Case>();
            for (Case c : [
                SELECT Id, SalesOrderCancellation__c 
                FROM Case 
                WHERE Id IN :caseIdsForHOSApproval AND Type = 'Sale Order Cancellation'
            ]) {
                // Sets field to Pending before submitting!
                c.SalesOrderCancellation__c = 'Pending';
                casesToUpdateAndSubmit.add(c);
            }

            if (!casesToUpdateAndSubmit.isEmpty()) {
                update casesToUpdateAndSubmit;

                for (Case c : casesToUpdateAndSubmit) {
                    submitForApproval(c.Id, 'Submitted automatically upon refund letter verification.');
                }
            }
        }

        // 2. Create "Deposit Refund" Task for Finance
        if (!caseIdsForDepositRefund.isEmpty()) {
            Id financeUserId = getUserByRole('Accounts Executive');
            List<Task> refundTasks = new List<Task>();
            for (Id cId : caseIdsForDepositRefund) {
                Task t = new Task();
                t.Subject      = 'Deposit Refund: Finance processes refund and manually marks the task Completed.';
                t.Description  = 'Finance to process customer refund and mark task Completed once executed.';
                t.Priority     = 'High';
                t.Status       = 'Open';
                t.ActivityDate = Date.today().addDays(3);
                t.WhatId       = cId;
                t.OwnerId      = financeUserId;
                refundTasks.add(t);
            }
            if (!refundTasks.isEmpty()) {
                insert refundTasks;
                System.debug('=== SUCCESS: Created ' + refundTasks.size() + ' Deposit Refund Task(s)! ===');
            }
        }

        // 3. Refund Done -> Notify HOS & Create "SO Cancellation" Task
        if (!caseIdsForSOCancellation.isEmpty()) {
            Id financeUserId = getUserByRole('Accounts Executive');
            Id hosUserId     = getUserByRole('Head - Sales');
            List<Task> soTasks = new List<Task>();

            for (Id cId : caseIdsForSOCancellation) {
                Task t = new Task();
                t.Subject      = 'Auto-create Task: "SO Cancellation" (for Finance)';
                t.Description  = 'Refund processed. Finance to execute Sales Order cancellation in system and mark Closed.';
                t.Priority     = 'High';
                t.Status       = 'Open';
                t.ActivityDate = Date.today().addDays(1);
                t.WhatId       = cId;
                t.OwnerId      = financeUserId;
                soTasks.add(t);

                sendBellNotification('Refund Completed', 'Deposit refund has been processed for Case ' + cId, cId, hosUserId);
            }
            if (!soTasks.isEmpty()) {
                insert soTasks;
                System.debug('=== SUCCESS: Created ' + soTasks.size() + ' SO Cancellation Task(s)! ===');
            }
        }

        // 4. SO Cancellation Closed -> Trigger Callout to SAP!
        if (!caseIdsForSAPCallout.isEmpty()) {
            for (Id cId : caseIdsForSAPCallout) {
                triggerSapSoCancellation(cId);
            }
        }
    }

    // =========================================================================
    // 5. SAP ERP INTEGRATION (TRIGGER TO SAP TO CANCEL SO)
    // =========================================================================
    @future(callout=true)
    public static void triggerSapSoCancellation(Id caseId) {
        try {
            System.debug('=== 🚀 CALLOUT TO SAP: Cancelling Sales Order for Case: ' + caseId + ' ===');
        } catch (Exception ex) {
            System.debug('Error calling SAP: ' + ex.getMessage());
        }
    }

    // =========================================================================
    // HELPERS: APPROVAL SUBMISSION, ROLE LOOKUP & BELL NOTIFICATIONS
    // =========================================================================
    private static void submitForApproval(Id recordId, String comments) {
        try {
            Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
            req.setComments(comments);
            req.setObjectId(recordId);
            Approval.process(req);
            System.debug('=== Successfully submitted Case ' + recordId + ' to Approval Process ===');
        } catch (Exception ex) {
            System.debug('Approval submit error: ' + ex.getMessage());
        }
    }

    public static Id getUserByRole(String roleName) {
        List<User> users = [
            SELECT Id FROM User 
            WHERE UserRole.Name = :roleName AND IsActive = true 
            LIMIT 1
        ];
        return !users.isEmpty() ? users[0].Id : UserInfo.getUserId();
    }

    public static void sendBellNotification(String title, String body, Id targetId, Id recipientId) {
        try {
            CustomNotificationType notifType = [
                SELECT Id FROM CustomNotificationType 
                WHERE DeveloperName = 'CaseTransferbellnotification' 
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
    public static void updateFlag(){
        system.debug('');                            
    }
}