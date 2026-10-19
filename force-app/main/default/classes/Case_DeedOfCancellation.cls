/* Author          : Nazir_Patel
   Description     : Handles the Deed of Cancellation dunning timeline:
                     - 1st, 2nd, Final Reminders (auto-completed)
                     - HOLD: Sends 30-day countdown email to customer & starts 30-day timer
                     - SEND: Sends Letter of Termination immediately (Customer + Case Owner) & alerts Legal
                     - Batch check: If 30-day HOLD expires without payment -> Sends Letter of Termination & alerts Legal
*/
public without sharing class Case_DeedOfCancellation {

    private static final String CUSTOMER_EMAIL = 'nazirsfdc@gmail.com';

    // =========================================================================
    // 1. MAIN BATCH PROCESSING (Runs Daily via PaymentScheduleDailyRun)
    // =========================================================================
    public static void processOverdueSchedules(List<Payment_Schedule__c> overdueSchedules) {
        
        Set<Id> oppIds = new Set<Id>();
        for (Payment_Schedule__c ps : overdueSchedules) {
            if (ps.Opportunity__c != null) oppIds.add(ps.Opportunity__c);
        }
        if (oppIds.isEmpty()) return;

        Map<Id, Case> oppToOpenCaseMap = new Map<Id, Case>();
        for (Case c : [
            SELECT Id, Status, Opportunity__c, AccountId, OwnerId, Owner.Email, CreatedDate 
            FROM Case 
            WHERE Opportunity__c IN :oppIds AND Type = 'Deed of Cancellation' AND Status != 'Closed'
        ]) {
            oppToOpenCaseMap.put(c.Opportunity__c, c);
        }

        Map<Id, Task> caseToLatestTaskMap = new Map<Id, Task>();
        if (!oppToOpenCaseMap.isEmpty()) {
            for (Task t : [
                SELECT Id, Subject, Status, CreatedDate, ActivityDate, WhatId 
                FROM Task 
                WHERE WhatId IN :oppToOpenCaseMap.values() 
                ORDER BY CreatedDate DESC
            ]) {
                if (!caseToLatestTaskMap.containsKey(t.WhatId)) {
                    caseToLatestTaskMap.put(t.WhatId, t);
                }
            }
        }

        List<Case> casesToInsert = new List<Case>();
        List<Task> tasksToInsert = new List<Task>();                                                                                                                                                                                          
        List<Messaging.SingleEmailMessage> emailsToSend = new List<Messaging.SingleEmailMessage>();

        Id csUserId    = getUserByRole('Executive Customer Service');
        Id legalUserId = getUserByRole('Head - Legal');

        for (Payment_Schedule__c ps : overdueSchedules) {
            
            // Scenario A: Brand new default -> Create Case & 1st Reminder
            if (!oppToOpenCaseMap.containsKey(ps.Opportunity__c)) {
                Case newCase = new Case();
                newCase.Type           = 'Deed of Cancellation';
                newCase.Subject        = 'Payment Default - Deed of Cancellation';
                newCase.Opportunity__c = ps.Opportunity__c;
                newCase.AccountId      = ps.Opportunity__r?.AccountId;
                newCase.Status         = 'New';
                newCase.OwnerId        = csUserId;
                casesToInsert.add(newCase);
            }
            // Scenario B: Existing Case -> Check deadlines
            else {
                Case existingCase = oppToOpenCaseMap.get(ps.Opportunity__c);
                Task latestTask   = caseToLatestTaskMap.get(existingCase.Id);
                if (latestTask == null) continue;

                Boolean is7DaysOverdue = (latestTask.ActivityDate != null && Date.today() >= latestTask.ActivityDate)
                                 || (latestTask.CreatedDate.date().daysBetween(Date.today()) >= 7);
                
                Boolean is30DaysOverdue=(latestTask.ActivityDate != null && Date.today() >= latestTask.ActivityDate)
                                 || (latestTask.CreatedDate.date().daysBetween(Date.today()) >= 30);

                // 1. After 7 days of 1st Reminder -> 2nd Reminder
                if (latestTask.Subject.contains('1st Reminder') && is7DaysOverdue) {
                    Task t = new Task();
                    t.Subject      = '2nd Reminder - Payment Due';
                    t.Description  = '7 days elapsed without payment. 2nd Reminder letter auto-sent.';
                    t.Priority     = 'High';
                    t.Status       = 'Completed';
                    t.ActivityDate = Date.today().addDays(7);
                    t.WhatId       = existingCase.Id;
                    t.OwnerId      = csUserId;
                    tasksToInsert.add(t);

                    emailsToSend.add(buildReminderEmail(existingCase.Id, CUSTOMER_EMAIL, '2nd Reminder'));
                }
                // 2. After 7 days of 2nd Reminder -> Final Reminder
                else if (latestTask.Subject.contains('2nd Reminder') && is7DaysOverdue) {
                    Task t = new Task();
                    t.Subject      = 'Final Reminder - Payment Due';
                    t.Description  = '7 days elapsed without payment. Final Reminder letter auto-sent.';
                    t.Priority     = 'High';
                    t.Status       = 'Completed';
                    t.ActivityDate = Date.today().addDays(7);
                    t.WhatId       = existingCase.Id;
                    t.OwnerId      = csUserId;
                    tasksToInsert.add(t);

                    emailsToSend.add(buildReminderEmail(existingCase.Id, CUSTOMER_EMAIL, 'Final Reminder'));
                }
                // 3. After 7 days of Final Reminder -> Create CS Action Task (STAYS OPEN!)
                else if (latestTask.Subject.contains('Final Reminder') && is7DaysOverdue) {
                    Task t = new Task();
                    t.Subject      = 'Notice of Termination - Review Required';
                    t.Description  = 'Customer failed 3rd payment reminder. Action required by CS:\n'
                                   + 'Click [Notice Action] button on Case to HOLD (30-day countdown) or SEND Letter of Termination.';
                    t.Priority     = 'High';
                    t.Status       = 'New'; 
                    t.ActivityDate = Date.today().addDays(2);
                    t.WhatId       = existingCase.Id;
                    t.OwnerId      = csUserId;
                    tasksToInsert.add(t);
					
                    sendBellNotification(
                        'Action Required: Notice of Termination Review', 
                        'Final reminder expired. Use the [Notice Action] button on Case ' + existingCase.Id, 
                        existingCase.Id, 
                        csUserId
                    );
                }
                // 4. After 30 days of HOLD -> Customer did not pay -> Send Letter of Termination to Customer & Case Owner & Notify Legal
                else if (latestTask.Subject.contains('Notice on Hold') && is30DaysOverdue) {
                    Task t = new Task();
                    t.Subject      = 'Letter of Termination - Escalated to Legal';
                    t.Description  = '30-day hold countdown elapsed without payment. Letter of Termination sent and matter escalated to Legal.';
                    t.Priority     = 'High';
                    t.Status       = 'Completed';
                    t.ActivityDate = Date.today();
                    t.WhatId       = existingCase.Id;
                    t.OwnerId      = csUserId;
                    tasksToInsert.add(t);

                    emailsToSend.add(buildLetterOfTerminationEmail(existingCase));
					
                      system.debug(' existingCase.Id ==>'+t.WhatId);
                    sendBellNotification(
                        'Deed of Cancellation - Legal Drafting Required', 
                        '30-day extension elapsed without payment. Please prepare Deed of Cancellation for Case ' + existingCase.Id, 
                        existingCase.Id, 
                        legalUserId
                    );
                }
            }
        }

        if (!casesToInsert.isEmpty()) {
            insert as system casesToInsert;

            for (Case c : casesToInsert) {
                Task t = new Task();
                t.Subject      = '1st Reminder - Payment Due';
                t.Description  = 'Payment overdue. 1st Reminder letter auto-sent.';
                t.Priority     = 'High';
                t.Status       = 'Completed';
                t.ActivityDate = Date.today().addDays(7);
                t.WhatId       = c.Id;
                t.OwnerId      = csUserId;
                tasksToInsert.add(t);

                emailsToSend.add(buildReminderEmail(c.Id, CUSTOMER_EMAIL, '1st Reminder'));
            }
        }

        if (!tasksToInsert.isEmpty()) {
            insert as system tasksToInsert;
        }

        if (!emailsToSend.isEmpty()) {
            try {
                Messaging.sendEmail(emailsToSend);
            } catch (Exception ex) {
                System.debug('Error sending emails: ' + ex.getMessage());
            }
        }
    }

    // =========================================================================
    // 2. CHECK STATUS FOR LWC BUTTON
    // =========================================================================
    @AuraEnabled
    public static Boolean checkNoticeStatus(Id caseId) {
        if (caseId == null) return false;

        List<Task> openTasks = [
            SELECT Id, Subject, Status, IsClosed 
            FROM Task 
            WHERE WhatId = :caseId 
              AND Subject LIKE '%Notice of Termination%' 
              AND IsClosed = false
            LIMIT 1
        ];
        return !openTasks.isEmpty();
    }

    // =========================================================================
    // 3. EXECUTE CS DECISION (HOLD VS SEND LETTER OF TERMINATION)
    // =========================================================================
    @AuraEnabled
    public static String handleTerminationAction(Id caseId, String actionType, String holdReason) {
        try {
            Id csUserId    = getUserByRole('Executive Customer Service');
            Id legalUserId = getUserByRole('Head - Legal');

            Case c = [
                SELECT Id, OwnerId, Owner.Email 
                FROM Case 
                WHERE Id = :caseId 
                LIMIT 1
            ];

            // 1. Close the open review task
            List<Task> openTasks = [
                SELECT Id, Status FROM Task 
                WHERE WhatId = :caseId AND Subject LIKE '%Notice of Termination%' AND IsClosed = false
            ];
            for (Task t : openTasks) {
                t.Status = 'Completed';
            }
            if (!openTasks.isEmpty()) update openTasks;

            // =================================================================
            // BRANCH 1: HOLD -> SEND 30-DAY COUNTDOWN EMAIL TO CUSTOMER
            // =================================================================
            if (actionType == 'HOLD') {
                // A. Send 30-Day Countdown Email to Customer
                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                mail.setToAddresses(new String[] { CUSTOMER_EMAIL });
                mail.setSubject('PAYMENT NOTICE: 30-Day Extension Granted (Countdown Started)');
                mail.setWhatId(caseId);
                mail.setSaveAsActivity(true);
                mail.setPlainTextBody(
                    'Dear Customer,\n\n'
                    + 'Your request for an extension on your overdue installment has been reviewed.\n'
                    + 'A 30-day countdown grace period has officially started from today.\n\n'
                    + 'Extension Remarks: ' + holdReason + '\n\n'
                    + 'Please note: If full settlement is not received within this 30-day window, '
                    + 'your agreement will be terminated and escalated to Legal for cancellation.\n\n'
                    + 'Thank you,\nJohn Keells Properties'
                );
                Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });

                // B. Create 30-day countdown task
                Task holdTask        = new Task();
                holdTask.Subject     = 'Notice on Hold - 30 Days Extension';
                holdTask.Description = 'Customer Service granted a 30-day extension. Countdown email sent to customer.\nReason: ' + holdReason;
                holdTask.Priority    = 'High';
                holdTask.Status      = 'Completed';
                holdTask.Status      = 'New';
                holdTask.ActivityDate = Date.today().addDays(30); // 30-day timer!
                holdTask.WhatId      = caseId;
                holdTask.OwnerId     = csUserId;
                insert holdTask;

                return 'SUCCESS: 30-Day Countdown email sent to customer and task placed on hold.';
            }
            // =================================================================
            // BRANCH 2: SEND -> SEND LETTER OF TERMINATION & NOTIFY LEGAL NOW!
            // =================================================================
            else if (actionType == 'SEND') {
                // A. Send Letter of Termination to Customer AND Case Owner!
                Messaging.sendEmail(new Messaging.SingleEmailMessage[] { buildLetterOfTerminationEmail(c) });
					
                // B. Create Completed Termination Task
                Task termTask        = new Task();
                termTask.Subject     = 'Letter of Termination - Escalated to Legal';
                termTask.Description = 'Letter of Termination sent immediately to Customer and Case Owner. Matter escalated to Legal.';
                termTask.Priority    = 'High';
                termTask.Status      = 'Completed';
                termTask.ActivityDate = Date.today();
                termTask.WhatId      = caseId;
                termTask.OwnerId     = csUserId;
                insert termTask;
                //flag to maintain for letter sent to customer
                c.Termination_Letter_Sent__c=true;
                Update c;
            
                
				  Case_SalesOrderCancellation.getSalesOrderCancellation(caseId);
                
                // C. Notify Legal Team
                sendBellNotification(
                    'Deed of Cancellation - Legal Drafting Required', 
                    'Letter of Termination issued. Please prepare Deed of Cancellation for Case ' + caseId, 
                    caseId, 
                    legalUserId
                );

                return 'SUCCESS: Letter of Termination sent to Customer and Case Owner, and Legal notified!';
            }

            return 'No action taken.';
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    // =========================================================================
    // HELPER: BUILD LETTER OF TERMINATION EMAIL (CUSTOMER + CASE OWNER)
    // =========================================================================
    private static Messaging.SingleEmailMessage buildLetterOfTerminationEmail(Case c) {
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        
        List<String> recipients = new List<String>{ CUSTOMER_EMAIL };
        if (c.Owner != null && String.isNotBlank(c.Owner.Email)) {
            recipients.add(c.Owner.Email);
        }

        mail.setToAddresses(recipients);
        mail.setSubject('FINAL NOTICE: Letter of Contract Termination - Case Ref: ' + c.Id);
        mail.setWhatId(c.Id);
        mail.setSaveAsActivity(true);

        String body = 'Dear Customer,\n\n'
                    + 'This communication serves as your formal Letter of Termination regarding the default in installment payment on your property.\n\n'
                    + 'The matter has now been escalated to our Legal team to execute the Deed of Cancellation.\n\n'
                    + 'Thank you,\n'
                    + 'John Keells Properties';
        mail.setPlainTextBody(body);
        return mail;
    }

    // =========================================================================
    // HELPER: BUILD REMINDER EMAIL
    // =========================================================================
    private static Messaging.SingleEmailMessage buildReminderEmail(Id caseId, String recipientEmail, String reminderStage) {
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new String[] { recipientEmail });
        mail.setSubject('Payment Overdue Notice: ' + reminderStage);
        mail.setWhatId(caseId);
        mail.setSaveAsActivity(true);

        String body = 'Dear Customer,\n\n'
                    + 'This is your ' + reminderStage + ' regarding the overdue installment on your property.\n\n'
                    + 'Please make the required payment to avoid default and contract cancellation.\n\n'
                    + 'Thank you,\n'
                    + 'John Keells Properties';
        mail.setPlainTextBody(body);
        return mail;
    }

    // =========================================================================
    // HELPER: ROLE LOOKUP & BELL NOTIFICATION
    // =========================================================================
    public static Id getUserByRole(String roleName) {
        List<User> users = [
            SELECT Id FROM User 
            WHERE UserRole.Name = :roleName AND IsActive = true WITH SYSTEM_MODE
            LIMIT 1
        ];
        return !users.isEmpty() ? users[0].Id : UserInfo.getUserId();
    }

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
    
}