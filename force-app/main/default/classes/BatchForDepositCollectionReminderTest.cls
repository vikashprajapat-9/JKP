@isTest
private class BatchForDepositCollectionReminderTest {

    @TestSetup
    static void setupTestData() {
        // Create Project
        Project__c proj = new Project__c();
        proj.Name = 'Test Reminder Project';
        proj.Deposit_Collection_Threshold__c = 3;
        insert proj;

        // Create Task Master for Deposit Amount Overdue if not already present
        List<Task_Master__c> existingTM = [
            SELECT Id FROM Task_Master__c 
            WHERE Task_Subject__c = 'Deposit Amount Overdue' AND Object_Type__c = 'Opportunity'
        ];
        if (existingTM.isEmpty()) {
            Task_Master__c tm = new Task_Master__c();
            tm.Task_Subject__c = 'Deposit Amount Overdue';
            tm.Object_Type__c = 'Opportunity';
            tm.Action_Type__c = 'Component';
            tm.Action_URL__c = 'depositOverdue';
            tm.IsActive__c = true;
            insert tm;
        }

        // 1. Opp Overdue with No Payment Schedule and No Receipt Log -> Overdue Task should be created
        Opportunity opp1 = new Opportunity();
        opp1.Name = 'Opp 1 Overdue No PS';
        opp1.StageName = 'Offer Letter and Deposit Collection';
        opp1.CloseDate = Date.today().addDays(30);
        opp1.Project__c = proj.Id;
        opp1.Offer_Letter_Sent__c = true;
        opp1.Offer_Letter_Sent_Date__c = Date.today().addDays(-5);
        opp1.Token_Amount__c = 1000;

        // 2. Opp Overdue with Payment Schedule 'Deposit Amount' of 5000 and Partial Receipt of 2000 -> Overdue Task should be created
        Opportunity opp2 = new Opportunity();
        opp2.Name = 'Opp 2 Overdue Partial Paid';
        opp2.StageName = 'Offer Letter and Deposit Collection';
        opp2.CloseDate = Date.today().addDays(30);
        opp2.Project__c = proj.Id;
        opp2.Offer_Letter_Sent__c = true;
        opp2.Offer_Letter_Sent_Date__c = Date.today().addDays(-4);

        // 3. Opp Overdue with Payment Schedule 'Deposit Amount' of 5000 and Full Receipt of 5000 -> NO task should be created
        Opportunity opp3 = new Opportunity();
        opp3.Name = 'Opp 3 Fully Paid';
        opp3.StageName = 'Offer Letter and Deposit Collection';
        opp3.CloseDate = Date.today().addDays(30);
        opp3.Project__c = proj.Id;
        opp3.Offer_Letter_Sent__c = true;
        opp3.Offer_Letter_Sent_Date__c = Date.today().addDays(-5);

        // 4. Opp Within Threshold (1 day ago, threshold is 3) -> NO task should be created
        Opportunity opp4 = new Opportunity();
        opp4.Name = 'Opp 4 Within Threshold';
        opp4.StageName = 'Offer Letter and Deposit Collection';
        opp4.CloseDate = Date.today().addDays(30);
        opp4.Project__c = proj.Id;
        opp4.Offer_Letter_Sent__c = true;
        opp4.Offer_Letter_Sent_Date__c = Date.today().addDays(-1);

        insert new List<Opportunity>{ opp1, opp2, opp3, opp4 };

        // Payment Schedules
        Payment_Schedule__c ps2 = new Payment_Schedule__c();
        ps2.Name = 'Deposit Amount';
        ps2.Opportunity__c = opp2.Id;
        ps2.Agreement_Value__c = 5000;

        Payment_Schedule__c ps3 = new Payment_Schedule__c();
        ps3.Name = 'Deposit Amount';
        ps3.Opportunity__c = opp3.Id;
        ps3.Agreement_Value__c = 5000;

        insert new List<Payment_Schedule__c>{ ps2, ps3 };

        // Receipt Logs
        Receipt_Log__c rl2 = new Receipt_Log__c();
        rl2.Opportunity__c = opp2.Id;
        rl2.Amount__c = 2000;

        Receipt_Log__c rl3 = new Receipt_Log__c();
        rl3.Opportunity__c = opp3.Id;
        rl3.Amount__c = 5000;

        insert new List<Receipt_Log__c>{ rl2, rl3 };
    }

    @isTest
    static void testBatchExecution() {
        Test.startTest();
        BatchForDepositCollectionReminder batch = new BatchForDepositCollectionReminder();
        Database.executeBatch(batch);
        Test.stopTest();

        List<Opportunity> opps = [SELECT Id, Name FROM Opportunity];
        Map<String, Id> oppMap = new Map<String, Id>();
        for (Opportunity o : opps) {
            oppMap.put(o.Name, o.Id);
        }

        // Verify task was created for Opp 1 and Opp 2
        List<Task> tasksForOpp1 = [SELECT Id, Subject, WhatId, Status, Priority, Task_Master__c FROM Task WHERE WhatId = :oppMap.get('Opp 1 Overdue No PS')];
        System.assertEquals(1, tasksForOpp1.size(), 'Opp 1 should have 1 Deposit Amount Overdue task created');
        System.assertEquals('Deposit Amount Overdue', tasksForOpp1[0].Subject);

        List<Task> tasksForOpp2 = [SELECT Id, Subject, WhatId FROM Task WHERE WhatId = :oppMap.get('Opp 2 Overdue Partial Paid')];
        System.assertEquals(1, tasksForOpp2.size(), 'Opp 2 should have 1 Deposit Amount Overdue task created');

        // Verify NO task was created for Opp 3 (fully paid)
        List<Task> tasksForOpp3 = [SELECT Id FROM Task WHERE WhatId = :oppMap.get('Opp 3 Fully Paid')];
        System.assertEquals(0, tasksForOpp3.size(), 'Opp 3 should not have any tasks because deposit was fully paid');

        // Verify NO task was created for Opp 4 (within threshold)
        List<Task> tasksForOpp4 = [SELECT Id FROM Task WHERE WhatId = :oppMap.get('Opp 4 Within Threshold')];
        System.assertEquals(0, tasksForOpp4.size(), 'Opp 4 should not have any tasks because it is within threshold');
    }

    @isTest
    static void testNoDuplicateTaskOnReExecution() {
        // Run batch once to create tasks
        Test.startTest();
        Database.executeBatch(new BatchForDepositCollectionReminder());
        Test.stopTest();

        // Run batch second time
        Database.executeBatch(new BatchForDepositCollectionReminder());

        List<Task> allOverdueTasks = [SELECT Id, WhatId FROM Task WHERE Subject = 'Deposit Amount Overdue'];
        // Should still only have 2 tasks (for Opp 1 and Opp 2), no duplicates
        System.assertEquals(2, allOverdueTasks.size(), 'Duplicate tasks should not be created on re-running the batch');
    }

    @isTest
    static void testScheduler() {
        Test.startTest();
        String cronExp = '0 0 0 15 3 ? 2030';
        String jobId = System.schedule('Test BatchForDepositCollectionReminder Scheduler', cronExp, new BatchForDepositCollectionReminder());
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Job should be scheduled successfully');
    }
}
