// Personal targets: the table for a Head of Sales, a viewer and an outsider, a change with its reason, back to the
// default, rows that never overlap, the reporting line, carrying targets over to the next period, a payee's own terms.
@IsTest
private class CommissionTargetServiceTest {

    // Designation keys of the test catalog (CommissionTestData.useCatalog)
    private static final String ADVISOR = 'Sales_Advisor';
    private static final String MANAGER = 'Senior_Manager_Advisor';
    private static final String SERVICE = 'Customer_Service';

    // One project with an approved configuration in force today, and the people of the test reporting line
    private class Scene {
        Project__c project;
        Commission_Config__c config;
        User head;
        User manager;
        User advisor;
        Decimal advisorDefault;
    }

    private static Scene prepare(String projectName) {
        CommissionTestData.useCatalog();
        Scene setup = new Scene();
        setup.head = CommissionTestData.headOfSales();
        setup.manager = CommissionTestData.seniorManager();
        setup.advisor = CommissionTestData.advisor();
        setup.project = CommissionTestData.project(projectName);
        setup.config = reload(CommissionTestData.insertApproved(setup.project.Id, Date.today().addDays(-30), Date.today().addDays(300)).Id);
        setup.advisorDefault = defaultTarget(setup.config.Id, ADVISOR);
        CommissionAccess.reset();
        CommissionNotifier.sentLog.clear();
        return setup;
    }

    // The configuration as stored; a lineage always has a reference (its own name when nothing wrote one)
    private static Commission_Config__c reload(Id configId) {
        Commission_Config__c config = [
            SELECT Id, Name, Reference__c, Version__c, Project__c, Start_Date__c, End_Date__c, Status__c
            FROM Commission_Config__c WHERE Id = :configId
        ];
        if (String.isBlank(config.Reference__c)) {
            Boolean earlier = CommissionTriggerHandler.bypass;
            CommissionTriggerHandler.bypass = true;
            try {
                config.Reference__c = config.Name;
                update config;
            } finally {
                CommissionTriggerHandler.bypass = earlier;
            }
        }
        return config;
    }

    private static Decimal defaultTarget(Id configId, String designation) {
        List<Commission_Rate__c> rates = [
            SELECT Target__c FROM Commission_Rate__c
            WHERE Config__c = :configId AND Designation__c = :designation AND Active__c = true LIMIT 1
        ];
        System.assertEquals(1, rates.size(), 'The test configuration pays ' + designation);
        return rates[0].Target__c;
    }

    private static CommissionDto.TargetSave changeOf(Scene setup, Id userId, String designation, Decimal target, Date fromDay, String reason) {
        CommissionDto.TargetChange change = new CommissionDto.TargetChange();
        change.userId = userId;
        change.designation = designation;
        change.target = target;
        CommissionDto.TargetSave asked = new CommissionDto.TargetSave();
        asked.projectId = setup.project.Id;
        asked.reference = setup.config.Reference__c;
        asked.effectiveFrom = fromDay;
        asked.reason = reason;
        asked.changes = new List<CommissionDto.TargetChange>{ change };
        return asked;
    }

    private static CommissionDto.TargetTable saveAs(User actor, CommissionDto.TargetSave asked) {
        CommissionDto.TargetTable result;
        System.runAs(actor) {
            result = CommissionTargetService.save(asked);
        }
        return result;
    }

    // The message the screen would show; null when the save went through
    private static String refusalFor(User actor, CommissionDto.TargetSave asked) {
        String message = null;
        System.runAs(actor) {
            try {
                CommissionTargetService.save(asked);
            } catch (AuraHandledException problem) {
                message = problem.getMessage();
            }
        }
        return message;
    }

    // A personal row written straight to the object, as a system step
    private static Commission_Target__c personal(Scene setup, Id userId, String designation, Decimal target, Date fromDay, Date toDay) {
        Commission_Target__c row = draftRow(setup, userId, designation, target, fromDay, toDay);
        CommissionTargetService.bypass = true;
        try {
            insert row;
        } finally {
            CommissionTargetService.bypass = false;
        }
        return row;
    }

    private static Commission_Target__c draftRow(Scene setup, Id userId, String designation, Decimal target, Date fromDay, Date toDay) {
        return new Commission_Target__c(
            Project__c = setup.project.Id,
            Reference__c = setup.config.Reference__c,
            Config__c = setup.config.Id,
            User__c = userId,
            Designation__c = designation,
            Target__c = target,
            Effective_From__c = fromDay,
            Effective_To__c = toDay,
            Reason__c = 'Agreed with the team'
        );
    }

    private static List<Commission_Target__c> targetsOf(Id userId) {
        return [
            SELECT Id, Project__c, Reference__c, Config__c, Designation__c, Target__c, Effective_From__c, Effective_To__c,
                Reason__c, Replaces__c
            FROM Commission_Target__c
            WHERE User__c = :userId
            ORDER BY Effective_From__c, Name
        ];
    }

    private static CommissionDto.TargetRow rowOf(CommissionDto.TargetTable table, Id userId) {
        for (CommissionDto.TargetGroup team : table.groups) {
            if (team.manager.userId == userId) {
                return team.manager;
            }
            for (CommissionDto.TargetRow member : team.members) {
                if (member.userId == userId) {
                    return member;
                }
            }
        }
        for (CommissionDto.TargetRow other : table.others) {
            if (other.userId == userId) {
                return other;
            }
        }
        return null;
    }

    // Numbers are compared by value: 12 and 12.00 are the same target
    private static void assertNumber(Decimal expected, Decimal actual, String message) {
        System.assert(expected == actual, message + ' (expected ' + expected + ', got ' + actual + ')');
    }

    // What the trigger says about one row written by this user; null when the row is accepted
    private static String triggerRefusal(User actor, Commission_Target__c row) {
        String message = null;
        System.runAs(actor) {
            Database.SaveResult result = Database.insert(row, false, AccessLevel.SYSTEM_MODE);
            if (!result.isSuccess()) {
                message = result.getErrors()[0].getMessage();
            }
        }
        return message;
    }

    // The same for a change of a stored row: only the fields given are changed
    private static String updateRefusal(User actor, Commission_Target__c change) {
        String message = null;
        System.runAs(actor) {
            Database.SaveResult result = Database.update(change, false, AccessLevel.SYSTEM_MODE);
            if (!result.isSuccess()) {
                message = result.getErrors()[0].getMessage();
            }
        }
        return message;
    }

    // ------------------------------------------------------------ the table

    @IsTest
    static void aHeadOfSalesSeesTheTeamUnderItsManager() {
        Scene setup = prepare('Targets Team');
        CommissionDto.TargetTable table;
        Test.startTest();
        System.runAs(setup.head) {
            table = CommissionTargetService.table(null, null);
        }
        Test.stopTest();

        System.assertEquals(setup.project.Id, table.projectId, 'The first project with an approved configuration is shown');
        System.assertEquals('Targets Team', table.projectName, 'The project is named');
        System.assertEquals(setup.config.Reference__c, table.reference, 'The configuration in force today is chosen');
        System.assertEquals(setup.config.Id, table.configId, 'The version in force gives the rates');
        System.assertEquals(null, table.message, 'A table with people has no empty-state message');
        System.assertEquals(true, table.canEdit, 'A Head of Sales maintains targets');
        System.assertEquals(1, table.projects.size(), 'One project has an approved configuration');
        System.assertEquals(1, table.configs.size(), 'The project has one current configuration');
        System.assertEquals(setup.config.Reference__c, table.configs[0].value, 'A configuration is chosen by its reference');
        System.assert(table.configs[0].label.contains(CommissionTargetService.formatDate(setup.config.Start_Date__c)), 'The option shows the period: ' + table.configs[0].label);

        System.assertEquals(1, table.groups.size(), 'The senior manager opens one team');
        CommissionDto.TargetGroup team = table.groups[0];
        System.assertEquals(setup.manager.Id, team.manager.userId, 'The manager whose target counts the advisors');
        System.assertEquals(true, team.manager.isManager, 'Marked as a manager row');
        System.assertEquals(1, team.manager.teamSize, 'One advisor reports to the manager');
        System.assertEquals(MANAGER, team.manager.designation, 'The manager holds the aggregating designation');
        System.assertEquals(1, team.members.size(), 'The advisor is listed under the manager');
        CommissionDto.TargetRow advisorRow = team.members[0];
        System.assertEquals(setup.advisor.Id, advisorRow.userId, 'The advisor of the test reporting line');
        System.assertEquals(ADVISOR, advisorRow.designation, 'The designation comes from the role');
        System.assertEquals(true, advisorRow.isDefault, 'Nobody has a personal target yet');
        assertNumber(setup.advisorDefault, advisorRow.target, 'The default of the configuration applies');
        System.assertEquals(setup.config.Start_Date__c, advisorRow.fromDate, 'A default applies from the start of the configuration');
        System.assertEquals(true, advisorRow.canEdit, 'The advisor is in the reporting line');
        System.assertEquals(null, advisorRow.actual, 'Actual sales come with the calculation phase');
        System.assertEquals(0, table.others.size(), 'Nobody is left without a manager');
    }

    @IsTest
    static void aPersonalTargetReplacesTheDefaultInTheTable() {
        Scene setup = prepare('Targets Personal');
        Decimal own = (setup.advisorDefault == null ? 10.0 : setup.advisorDefault) + 3;
        personal(setup, setup.advisor.Id, ADVISOR, own, Date.today().addDays(-2), null);
        // A row that is over and a row that starts later do not count today
        personal(setup, setup.manager.Id, MANAGER, 99, Date.today().addDays(-20), Date.today().addDays(-10));
        personal(setup, setup.manager.Id, MANAGER, 77, Date.today().addDays(30), null);

        CommissionDto.TargetTable table;
        System.runAs(setup.head) {
            table = CommissionTargetService.table(setup.project.Id, setup.config.Reference__c);
        }
        CommissionDto.TargetRow advisorRow = rowOf(table, setup.advisor.Id);
        assertNumber(own, advisorRow.target, 'The personal target in force today is shown');
        System.assertEquals(false, advisorRow.isDefault, 'It is not the default');
        System.assertEquals(Date.today().addDays(-2), advisorRow.fromDate, 'With the day it applies from');
        System.assertEquals('Agreed with the team', advisorRow.reason, 'And its reason');
        assertNumber(setup.advisorDefault, advisorRow.defaultTarget, 'The default stays known for Use default');
        System.assertNotEquals(null, advisorRow.setOn, 'The day it was set is shown');
        CommissionDto.TargetRow managerRow = rowOf(table, setup.manager.Id);
        System.assertEquals(true, managerRow.isDefault, 'A closed row and a future row leave the default in force today');
    }

    @IsTest
    static void aViewerSeesEveryoneButCannotEdit() {
        Scene setup = prepare('Targets Viewer');
        CommissionDto.TargetTable table;
        System.runAs(CommissionTestData.finance()) {
            table = CommissionTargetService.table(setup.project.Id, setup.config.Reference__c);
        }
        System.assertEquals(false, table.canEdit, 'Finance reads the targets');
        CommissionDto.TargetRow advisorRow = rowOf(table, setup.advisor.Id);
        System.assertNotEquals(null, advisorRow, 'A viewer is not limited to a reporting line');
        System.assertEquals(false, advisorRow.canEdit, 'A viewer cannot edit a row');
        System.assertNotEquals(null, rowOf(table, setup.manager.Id), 'The manager is shown as well');
    }

    @IsTest
    static void anOutsiderIsRefused() {
        Scene setup = prepare('Targets Outsider');
        User outsider = CommissionTestData.outsider();
        CommissionAccess.reset();
        Boolean refused = false;
        List<CommissionDto.MyTerm> terms;
        System.runAs(outsider) {
            try {
                CommissionTargetService.table(setup.project.Id, null);
            } catch (AuraHandledException problem) {
                refused = true;
                System.assertEquals(Label.Commission_Common_No_Access, problem.getMessage(), 'The no-access message is shown');
            }
            terms = CommissionTargetService.myTerms();
        }
        System.assert(refused, 'Someone without a capability does not get the table');
        System.assertEquals(0, terms.size(), 'And has no commission terms');
        System.assertNotEquals(null, refusalFor(outsider, changeOf(setup, setup.advisor.Id, ADVISOR, 5, Date.today(), 'No right')),
            'And cannot save a target');
        System.assertEquals(0, targetsOf(setup.advisor.Id).size(), 'Nothing was written');
    }

    @IsTest
    static void theEmptyStatesSayWhy() {
        CommissionTestData.useCatalog();
        User finance = CommissionTestData.finance();
        Project__c bare = CommissionTestData.project('Targets Bare');
        CommissionAccess.reset();
        CommissionDto.TargetTable nothing;
        System.runAs(finance) {
            nothing = CommissionTargetService.table(null, null);
        }
        System.assertEquals(Label.Commission_Target_No_Configuration, nothing.message, 'No project has an approved configuration');
        System.assertEquals(0, nothing.projects.size(), 'So no project can be chosen');

        Project__c other = CommissionTestData.project('Targets Covered');
        Commission_Config__c config = reload(CommissionTestData.insertApproved(other.Id, Date.today().addDays(-5), Date.today().addDays(60)).Id);
        CommissionDto.TargetTable ofBare;
        CommissionDto.TargetTable fallback;
        System.runAs(finance) {
            ofBare = CommissionTargetService.table(bare.Id, null);
            fallback = CommissionTargetService.table(other.Id, 'CC-NOT-THERE');
        }
        System.assert(ofBare.message.contains('Targets Bare'), 'The project without a configuration is named: ' + ofBare.message);
        System.assertEquals(0, ofBare.groups.size(), 'And has no rows');
        System.assertEquals(1, ofBare.projects.size(), 'The project that has one can be chosen instead');
        System.assertEquals(config.Reference__c, fallback.reference, 'An unknown reference falls back to the configuration in force');
    }

    // ------------------------------------------------------------ saving

    @IsTest
    static void aTargetChangeIsSavedWithItsReason() {
        Scene setup = prepare('Targets Change');
        Decimal wanted = (setup.advisorDefault == null ? 10.0 : setup.advisorDefault) + 2;
        Test.startTest();
        CommissionDto.TargetTable table = saveAs(setup.head, changeOf(setup, setup.advisor.Id, ADVISOR, wanted, Date.today(), '  Larger unit mix  '));
        Test.stopTest();

        List<Commission_Target__c> rows = targetsOf(setup.advisor.Id);
        System.assertEquals(1, rows.size(), 'One personal row was created');
        assertNumber(wanted, rows[0].Target__c, 'With the new target');
        System.assertEquals('Larger unit mix', rows[0].Reason__c, 'And the reason, trimmed');
        System.assertEquals(Date.today(), rows[0].Effective_From__c, 'From the chosen day');
        System.assertEquals(null, rows[0].Effective_To__c, 'Still in force');
        System.assertEquals(setup.config.Id, rows[0].Config__c, 'The version in force when it was set');
        System.assertEquals(setup.config.Reference__c, rows[0].Reference__c, 'It belongs to the lineage');
        System.assertEquals(setup.project.Id, rows[0].Project__c, 'And to the project');

        CommissionDto.TargetRow advisorRow = rowOf(table, setup.advisor.Id);
        assertNumber(wanted, advisorRow.target, 'The returned table shows the new target');
        System.assertEquals(false, advisorRow.isDefault, 'As a personal target');

        Boolean told = false;
        for (CommissionNotifier.Sent entry : CommissionNotifier.sentLog) {
            if (entry.title == Label.Commission_Notify_Target_Person_Title && entry.userIds.contains(setup.advisor.Id)) {
                told = true;
                System.assert(entry.body.contains('Larger unit mix'), 'The person is told the reason: ' + entry.body);
                System.assert(entry.body.contains(CommissionTargetService.formatNumber(wanted)), 'And the new target: ' + entry.body);
            }
        }
        System.assert(told, 'The person is told about the new target');
    }

    @IsTest
    static void aLaterChangeClosesTheRowInForce() {
        Scene setup = prepare('Targets Later');
        Date today = Date.today();
        Test.startTest();
        saveAs(setup.head, changeOf(setup, setup.advisor.Id, ADVISOR, 12, today, 'First'));
        saveAs(setup.head, changeOf(setup, setup.advisor.Id, ADVISOR, 15, today.addDays(10), 'Second'));

        List<Commission_Target__c> rows = targetsOf(setup.advisor.Id);
        System.assertEquals(2, rows.size(), 'The change added a row');
        System.assertEquals(today.addDays(9), rows[0].Effective_To__c, 'The earlier row ends the day before');
        System.assertEquals(today.addDays(10), rows[1].Effective_From__c, 'The new row starts on the chosen day');
        System.assertEquals(rows[0].Id, rows[1].Replaces__c, 'And names the row it replaces');
        System.assertEquals(null, rows[1].Effective_To__c, 'It stays in force');

        // The same day again: the row is corrected, not doubled
        CommissionDto.TargetTable table = saveAs(setup.head, changeOf(setup, setup.advisor.Id, ADVISOR, 16, today.addDays(10), 'Corrected'));
        Test.stopTest();
        rows = targetsOf(setup.advisor.Id);
        System.assertEquals(2, rows.size(), 'A change on the day a row starts corrects that row');
        assertNumber(16, rows[1].Target__c, 'With the new target');
        System.assertEquals('Corrected', rows[1].Reason__c, 'And the new reason');
        assertNumber(12, rowOf(table, setup.advisor.Id).target, 'Today the first row is still in force');
    }

    @IsTest
    static void aChangeBetweenTwoRowsFitsBetweenThem() {
        Scene setup = prepare('Targets Between');
        Date today = Date.today();
        personal(setup, setup.advisor.Id, ADVISOR, 12, today, today.addDays(9));
        personal(setup, setup.advisor.Id, ADVISOR, 15, today.addDays(10), null);

        Test.startTest();
        // The new row runs until the row it replaces would have ended
        saveAs(setup.head, changeOf(setup, setup.advisor.Id, ADVISOR, 13, today.addDays(5), 'In between'));
        List<Commission_Target__c> rows = targetsOf(setup.advisor.Id);
        System.assertEquals(3, rows.size(), 'One more row');
        System.assertEquals(today.addDays(4), rows[0].Effective_To__c, 'The first row is cut');
        System.assertEquals(today.addDays(5), rows[1].Effective_From__c, 'The new row follows it');
        System.assertEquals(today.addDays(9), rows[1].Effective_To__c, 'And ends before the later row starts');
        System.assertEquals(today.addDays(10), rows[2].Effective_From__c, 'The later row is untouched');

        // The same target again changes nothing
        saveAs(setup.head, changeOf(setup, setup.advisor.Id, ADVISOR, 13, today.addDays(6), 'Nothing new'));
        System.assertEquals(3, targetsOf(setup.advisor.Id).size(), 'An unchanged target writes no row');

        // A first target for someone who only has a later row ends the day before that row
        personal(setup, setup.manager.Id, MANAGER, 40, today.addDays(20), null);
        saveAs(setup.head, changeOf(setup, setup.manager.Id, MANAGER, 35, today, 'Until the new team starts'));
        Test.stopTest();
        rows = targetsOf(setup.manager.Id);
        System.assertEquals(2, rows.size(), 'The manager has two rows');
        System.assertEquals(today.addDays(19), rows[0].Effective_To__c, 'The new one ends the day before the later row');
        System.assertEquals(null, rows[0].Replaces__c, 'It replaces no row');
    }

    @IsTest
    static void backToTheDefaultClosesThePersonalRow() {
        Scene setup = prepare('Targets Default');
        Date today = Date.today();
        personal(setup, setup.advisor.Id, ADVISOR, 12, today.addDays(-5), null);

        Test.startTest();
        CommissionDto.TargetTable table = saveAs(setup.head, changeOf(setup, setup.advisor.Id, ADVISOR, null, today, 'Back to normal'));
        // Back to default twice changes nothing
        saveAs(setup.head, changeOf(setup, setup.advisor.Id, ADVISOR, null, today, 'Again'));
        Test.stopTest();

        List<Commission_Target__c> rows = targetsOf(setup.advisor.Id);
        System.assertEquals(1, rows.size(), 'No row is deleted and none is added');
        System.assertEquals(today.addDays(-1), rows[0].Effective_To__c, 'The personal row ends the day before');
        assertNumber(12, rows[0].Target__c, 'And keeps what it was');
        CommissionDto.TargetRow advisorRow = rowOf(table, setup.advisor.Id);
        System.assertEquals(true, advisorRow.isDefault, 'The default is in force again');
        assertNumber(setup.advisorDefault, advisorRow.target, 'With the target of the configuration');
        System.assertEquals('Back to normal', rows[0].Reason__c, 'With the reason it ended for');
        Integer notices = 0;
        for (CommissionNotifier.Sent entry : CommissionNotifier.sentLog) {
            if (entry.title == Label.Commission_Notify_Target_Person_Title && entry.userIds.contains(setup.advisor.Id)) {
                notices++;
                System.assert(entry.body.contains('Back to normal'), 'The person is told the reason of the reset: ' + entry.body);
            }
        }
        System.assertEquals(1, notices, 'The person is told about the reset, once');
    }

    @IsTest
    static void backToTheDefaultOnTheFirstDayLeavesTheRowWithoutEffect() {
        Scene setup = prepare('Targets First Day');
        Date day = Date.today().addDays(3);
        personal(setup, setup.advisor.Id, ADVISOR, 14, day, null);

        Test.startTest();
        // A row that starts on the chosen day cannot end before it starts
        CommissionDto.TargetTable table = saveAs(setup.head, changeOf(setup, setup.advisor.Id, ADVISOR, null, day, 'Not after all'));
        List<Commission_Target__c> rows = targetsOf(setup.advisor.Id);
        System.assertEquals(1, rows.size(), 'The row is kept');
        System.assertEquals(rows[0].Effective_From__c, rows[0].Effective_To__c, 'It ends on the day it starts');
        assertNumber(setup.advisorDefault, rows[0].Target__c, 'And holds the default, so it has no effect');
        System.assertEquals('Not after all', rows[0].Reason__c, 'With the reason of the reset');
        System.assertEquals(true, rowOf(table, setup.advisor.Id).isDefault, 'The table shows the default');

        // Setting a target on that day again brings the row back into force
        saveAs(setup.head, changeOf(setup, setup.advisor.Id, ADVISOR, 15, day, 'After all'));
        Test.stopTest();
        rows = targetsOf(setup.advisor.Id);
        System.assertEquals(1, rows.size(), 'Still one row');
        assertNumber(15, rows[0].Target__c, 'The row holds the new target');
        System.assertEquals(null, rows[0].Effective_To__c, 'And is in force from its day on');
    }

    @IsTest
    static void aSaveChecksWhatItIsGiven() {
        Scene setup = prepare('Targets Checks');
        Date today = Date.today();
        User finance = CommissionTestData.finance();
        CommissionAccess.reset();

        Test.startTest();
        CommissionDto.TargetSave empty = changeOf(setup, setup.advisor.Id, ADVISOR, 12, today, 'Reason');
        empty.changes = new List<CommissionDto.TargetChange>();
        System.assertEquals(Label.Commission_Target_Nothing_To_Save, refusalFor(setup.head, empty), 'A save needs a change');
        System.assertEquals(Label.Commission_Target_Reason_Required, refusalFor(setup.head, changeOf(setup, setup.advisor.Id, ADVISOR, 12, today, '  ')),
            'A reason is mandatory');
        System.assertNotEquals(null, refusalFor(setup.head, changeOf(setup, setup.advisor.Id, ADVISOR, 12, today, 'x'.repeat(300))),
            'A reason that does not fit is refused');
        System.assertEquals(Label.Commission_Target_From_Required, refusalFor(setup.head, changeOf(setup, setup.advisor.Id, ADVISOR, 12, null, 'Reason')),
            'The day is mandatory');
        String early = refusalFor(setup.head, changeOf(setup, setup.advisor.Id, ADVISOR, 12, setup.config.Start_Date__c.addDays(-1), 'Reason'));
        System.assert(early != null && early.contains(CommissionTargetService.formatDate(setup.config.Start_Date__c)),
            'A target cannot apply before the configuration starts: ' + early);
        System.assertNotEquals(null, refusalFor(setup.head, changeOf(setup, setup.advisor.Id, ADVISOR, 12, setup.config.End_Date__c.addDays(1), 'Reason')),
            'Nor after it ends');
        System.assertEquals(Label.Commission_Target_Negative, refusalFor(setup.head, changeOf(setup, setup.advisor.Id, ADVISOR, -1, today, 'Reason')),
            'A target cannot be negative');
        CommissionDto.TargetSave stale = changeOf(setup, setup.advisor.Id, ADVISOR, 12, today, 'Reason');
        stale.reference = 'CC-NOT-THERE';
        System.assertEquals(Label.Commission_Target_Config_Missing, refusalFor(setup.head, stale), 'The configuration must be approved and current');
        System.assertEquals(Label.Commission_Target_Not_Eligible, refusalFor(setup.head, changeOf(setup, finance.Id, ADVISOR, 12, today, 'Reason')),
            'Only a holder of the designation can have a target');
        System.assertNotEquals(null, refusalFor(finance, changeOf(setup, setup.advisor.Id, ADVISOR, 12, today, 'Reason')),
            'Finance cannot maintain targets');
        Test.stopTest();
        System.assertEquals(0, targetsOf(setup.advisor.Id).size(), 'None of these wrote a row');
    }

    // ------------------------------------------------------------ the reporting line and the trigger

    // Gives a designation of the test catalog to the holders of another role. The catalog is read from the
    // injected records every time, so the change applies from here on.
    private static void giveDesignationTo(String designation, String roleName) {
        List<Commission_Designation__mdt> changed = new List<Commission_Designation__mdt>();
        for (Commission_Designation__mdt record : CommissionCatalog.testDesignations) {
            if (record.DeveloperName != designation) {
                changed.add(record);
                continue;
            }
            // A custom metadata record is rebuilt from JSON: its fields cannot simply be assigned
            Map<String, Object> values = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(record));
            values.put('User_Roles__c', roleName);
            changed.add((Commission_Designation__mdt) JSON.deserialize(JSON.serialize(values), Commission_Designation__mdt.class));
        }
        CommissionCatalog.testDesignations = changed;
        CommissionAccess.reset();
    }

    @IsTest
    static void someoneOutsideTheReportingLineIsRefused() {
        Scene setup = prepare('Targets Line');
        // Someone who holds a paid designation with a target and reports to nobody
        User stray = CommissionTestData.outsider();
        giveDesignationTo(SERVICE, CommissionTestData.ROLE_OUTSIDER);

        Test.startTest();
        CommissionDto.TargetTable table;
        System.runAs(setup.head) {
            table = CommissionTargetService.table(setup.project.Id, setup.config.Reference__c);
        }
        System.assertEquals(null, rowOf(table, stray.Id), 'A Head of Sales only sees the people below them');
        System.assertNotEquals(null, rowOf(table, setup.advisor.Id), 'Their own advisor is there');

        String refusal = refusalFor(setup.head, changeOf(setup, stray.Id, SERVICE, 20, Date.today(), 'Not mine'));
        System.assertEquals(CommissionTargetService.fill(Label.Commission_Target_Outside_Line_Named, new List<Object>{ stray.Name }), refusal,
            'The refusal names the person outside the reporting line');
        System.assertEquals(Label.Commission_Target_Outside_Line,
            triggerRefusal(setup.head, draftRow(setup, stray.Id, SERVICE, 20, Date.today(), null)),
            'The trigger refuses the same when the row is written directly');
        System.assertEquals(0, targetsOf(stray.Id).size(), 'Nothing was written for them');

        // A viewer sees them, after the teams
        System.runAs(CommissionTestData.finance()) {
            table = CommissionTargetService.table(setup.project.Id, setup.config.Reference__c);
        }
        Test.stopTest();
        Boolean inOthers = false;
        for (CommissionDto.TargetRow other : table.others) {
            inOthers = inOthers || other.userId == stray.Id;
        }
        System.assert(inOthers, 'A viewer sees everybody; someone without a manager in the table is listed after the teams');
        System.assertEquals(SERVICE, rowOf(table, stray.Id).designation, 'With the designation their role holds');
    }

    @IsTest
    static void theTriggerKeepsTargetsApart() {
        Scene setup = prepare('Targets Rules');
        Date today = Date.today();
        Commission_Target__c existing = personal(setup, setup.advisor.Id, ADVISOR, 12, today, today.addDays(20));

        Test.startTest();
        System.assertEquals(Label.Commission_Target_Overlap,
            triggerRefusal(setup.head, draftRow(setup, setup.advisor.Id, ADVISOR, 14, today.addDays(20), null)),
            'Two targets of one person cannot share a day');
        System.assertEquals(Label.Commission_Target_Overlap,
            triggerRefusal(setup.head, draftRow(setup, setup.advisor.Id, ADVISOR, 14, today.addDays(-10), null)),
            'An open-ended row overlaps everything after its start');
        Commission_Target__c noReason = draftRow(setup, setup.advisor.Id, ADVISOR, 14, today.addDays(21), null);
        noReason.Reason__c = null;
        System.assertEquals(Label.Commission_Target_Reason_Required, triggerRefusal(setup.head, noReason), 'A reason is mandatory');
        System.assertEquals(Label.Commission_Target_Dates_Order,
            triggerRefusal(setup.head, draftRow(setup, setup.advisor.Id, ADVISOR, 14, today.addDays(30), today.addDays(25))),
            'A row cannot end before it starts');
        System.assertEquals(Label.Commission_Target_Negative,
            triggerRefusal(setup.head, draftRow(setup, setup.advisor.Id, ADVISOR, -2, today.addDays(21), null)),
            'A target cannot be negative');
        System.assertEquals(Label.Commission_Target_Only_Head,
            triggerRefusal(CommissionTestData.finance(), draftRow(setup, setup.advisor.Id, ADVISOR, 14, today.addDays(21), null)),
            'Only a target editor writes targets');
        System.assertEquals(null,
            triggerRefusal(setup.head, draftRow(setup, setup.advisor.Id, ADVISOR, 14, today.addDays(21), today.addDays(40))),
            'A row after the existing one is accepted');
        // Another designation or lineage is a different target
        System.assertEquals(null,
            triggerRefusal(setup.head, draftRow(setup, setup.advisor.Id, MANAGER, 14, today, null)),
            'The same days for another designation do not clash');

        // Two rows of one save are compared with each other as well
        List<Commission_Target__c> pair = new List<Commission_Target__c>{
            draftRow(setup, setup.manager.Id, MANAGER, 30, today, null),
            draftRow(setup, setup.manager.Id, MANAGER, 31, today.addDays(3), null)
        };
        System.runAs(setup.head) {
            List<Database.SaveResult> results = Database.insert(pair, false, AccessLevel.SYSTEM_MODE);
            System.assertEquals(true, results[0].isSuccess(), 'The first row of the pair is accepted');
            System.assertEquals(false, results[1].isSuccess(), 'The second one overlaps the first');

            // An update is checked like an insert; a delete is always refused
            existing.Effective_To__c = today.addDays(30);
            Database.SaveResult stretched = Database.update(existing, false, AccessLevel.SYSTEM_MODE);
            System.assertEquals(false, stretched.isSuccess(), 'Stretching a row over the next one is refused');
            existing.Effective_To__c = today.addDays(15);
            Database.SaveResult shortened = Database.update(existing, false, AccessLevel.SYSTEM_MODE);
            System.assertEquals(true, shortened.isSuccess(), 'Shortening it is fine');
            Database.DeleteResult removed = Database.delete(existing, false, AccessLevel.SYSTEM_MODE);
            System.assertEquals(false, removed.isSuccess(), 'A target row is never deleted');
        }
        // Whoever may delete the record as far as Salesforce is concerned (its owner, an administrator) gets the trigger's message
        Database.DeleteResult refused = Database.delete(existing, false, AccessLevel.SYSTEM_MODE);
        System.assertEquals(false, refused.isSuccess(), 'Not by its owner either');
        System.assertEquals(Label.Commission_Target_No_Delete, refused.getErrors()[0].getMessage(), 'With a message that says what to do');
        Test.stopTest();
    }

    @IsTest
    static void aSavedTargetIsOnlyChangedOnTheScreen() {
        Scene setup = prepare('Targets In Place');
        Date today = Date.today();
        Commission_Target__c row = personal(setup, setup.advisor.Id, ADVISOR, 12, today, null);

        Test.startTest();
        System.assertEquals(Label.Commission_Target_Use_Screen,
            updateRefusal(setup.head, new Commission_Target__c(Id = row.Id, Target__c = 15, Reason__c = 'Typed on the record')),
            'The target of a saved row is not changed in place, with or without a new reason');
        System.assertEquals(Label.Commission_Target_Use_Screen,
            updateRefusal(setup.head, new Commission_Target__c(Id = row.Id, Target__c = 15)),
            'Nor with the reason it already had');
        System.assertEquals(Label.Commission_Target_Use_Screen,
            updateRefusal(setup.head, new Commission_Target__c(Id = row.Id, Effective_From__c = today.addDays(-3))),
            'Nor the day it applies from');
        System.assertEquals(Label.Commission_Target_Use_Screen,
            updateRefusal(setup.head, new Commission_Target__c(Id = row.Id, Designation__c = MANAGER)),
            'Nor its designation');
        System.assertEquals(Label.Commission_Target_Use_Screen,
            updateRefusal(setup.head, new Commission_Target__c(Id = row.Id, Reference__c = 'CC-OTHER')),
            'Nor its configuration');
        System.assertEquals(Label.Commission_Target_Use_Screen,
            updateRefusal(setup.head, new Commission_Target__c(Id = row.Id, User__c = setup.manager.Id)),
            'Nor its person, even one of the same reporting line');

        // The last day and the reason stay open, as before
        System.assertEquals(null,
            updateRefusal(setup.head, new Commission_Target__c(Id = row.Id, Effective_To__c = today.addDays(30), Reason__c = 'Ends with the quarter')),
            'The last day and the reason of a saved row can be changed');
        Commission_Target__c noReason = new Commission_Target__c(Id = row.Id);
        noReason.Reason__c = null;
        System.assertEquals(Label.Commission_Target_Reason_Required, updateRefusal(setup.head, noReason), 'The reason cannot be emptied');

        List<Commission_Target__c> rows = targetsOf(setup.advisor.Id);
        System.assertEquals(1, rows.size(), 'The row still belongs to the advisor');
        assertNumber(12, rows[0].Target__c, 'With the target it was saved with');
        System.assertEquals(today, rows[0].Effective_From__c, 'From the same day');
        System.assertEquals(ADVISOR, rows[0].Designation__c, 'For the same designation');
        System.assertEquals(setup.config.Reference__c, rows[0].Reference__c, 'In the same configuration');
        System.assertEquals(today.addDays(30), rows[0].Effective_To__c, 'Only the last day changed');
        System.assertEquals('Ends with the quarter', rows[0].Reason__c, 'And the reason');
        System.assertEquals(0, targetsOf(setup.manager.Id).size(), 'Nothing moved to the manager');

        // The screen still changes it: a correction on the first day of the row is a system step of the service
        saveAs(setup.head, changeOf(setup, setup.advisor.Id, ADVISOR, 15, today, 'Changed on the screen'));
        Test.stopTest();
        rows = targetsOf(setup.advisor.Id);
        System.assertEquals(1, rows.size(), 'The Targets screen corrects the row, it does not add one');
        assertNumber(15, rows[0].Target__c, 'With the new target');
        System.assertEquals('Changed on the screen', rows[0].Reason__c, 'And the reason given on the screen');
        System.assertEquals(today.addDays(30), rows[0].Effective_To__c, 'The last day stays as it was set');
        Integer notices = 0;
        for (CommissionNotifier.Sent entry : CommissionNotifier.sentLog) {
            if (entry.title == Label.Commission_Notify_Target_Person_Title && entry.userIds.contains(setup.advisor.Id)) {
                notices++;
            }
        }
        System.assertEquals(1, notices, 'And only that change is told to the person');
    }

    @IsTest
    static void aRowOfSomeoneOutsideTheLineIsNotTakenOver() {
        Scene setup = prepare('Targets Taken');
        // Someone who reports to nobody has a personal target
        User stray = CommissionTestData.outsider();
        CommissionAccess.reset();
        Commission_Target__c theirs = personal(setup, stray.Id, SERVICE, 20, Date.today(), null);

        Test.startTest();
        System.assertEquals(Label.Commission_Target_Outside_Line,
            updateRefusal(setup.head, new Commission_Target__c(Id = theirs.Id, User__c = setup.advisor.Id)),
            'A row of someone outside the line cannot be given to someone inside it');
        System.assertEquals(Label.Commission_Target_Outside_Line,
            updateRefusal(setup.head, new Commission_Target__c(Id = theirs.Id, Effective_To__c = Date.today().addDays(5))),
            'Nor closed or changed in any other way');
        // The other way round: a row of the line cannot be given away either
        Commission_Target__c own = personal(setup, setup.advisor.Id, ADVISOR, 12, Date.today(), null);
        System.assertEquals(Label.Commission_Target_Outside_Line,
            updateRefusal(setup.head, new Commission_Target__c(Id = own.Id, User__c = stray.Id)),
            'A row of the line cannot be given to someone outside it');

        // Someone who is not limited to a reporting line gets the rule of a saved target instead
        CommissionTestData.setSetting(new Map<String, Object>{ 'Target_Profiles__c' => setup.head.Profile.Name });
        System.assertEquals(Label.Commission_Target_Use_Screen,
            updateRefusal(setup.head, new Commission_Target__c(Id = theirs.Id, User__c = setup.advisor.Id)),
            'Without a reporting line the row still keeps its person');
        System.assertEquals(null,
            updateRefusal(setup.head, new Commission_Target__c(Id = theirs.Id, Effective_To__c = Date.today().addDays(5))),
            'And its last day can be set');
        Test.stopTest();

        List<Commission_Target__c> rows = targetsOf(stray.Id);
        System.assertEquals(1, rows.size(), 'The row still belongs to the person it was set for');
        assertNumber(20, rows[0].Target__c, 'With their target');
        System.assertEquals(1, targetsOf(setup.advisor.Id).size(), 'And the advisor only has their own row');
    }

    // ------------------------------------------------------------ next period

    @IsTest
    static void personalTargetsAreCarriedOverToTheNextPeriod() {
        Scene setup = prepare('Targets Carry');
        Date nextStart = setup.config.End_Date__c.addDays(1);
        Commission_Config__c following = reload(CommissionTestData.insertApproved(setup.project.Id, nextStart, nextStart.addDays(364)).Id);
        System.assertNotEquals(setup.config.Reference__c, following.Reference__c, 'The next period is a new lineage');

        Commission_Target__c kept = personal(setup, setup.advisor.Id, ADVISOR, 14, Date.today().addDays(-5), null);
        // Over before the period ends: not carried
        personal(setup, setup.manager.Id, MANAGER, 40, Date.today().addDays(-20), Date.today().addDays(-1));

        Test.startTest();
        CommissionTargetService.carryOver(setup.config.Reference__c, following);
        // A second run adds nothing, and incomplete calls do nothing
        CommissionTargetService.carryOver(setup.config.Reference__c, following);
        CommissionTargetService.carryOver(null, following);
        CommissionTargetService.carryOver(setup.config.Reference__c, null);
        Test.stopTest();

        List<Commission_Target__c> carried = [
            SELECT User__c, Designation__c, Target__c, Effective_From__c, Effective_To__c, Config__c, Project__c, Reason__c, Replaces__c
            FROM Commission_Target__c WHERE Reference__c = :following.Reference__c
        ];
        System.assertEquals(1, carried.size(), 'Only the target still in force at the end of the period is copied, once');
        System.assertEquals(setup.advisor.Id, carried[0].User__c, 'For the same person');
        System.assertEquals(ADVISOR, carried[0].Designation__c, 'And designation');
        assertNumber(14, carried[0].Target__c, 'With the same target');
        System.assertEquals(nextStart, carried[0].Effective_From__c, 'Effective from the first day of the new period');
        System.assertEquals(null, carried[0].Effective_To__c, 'And in force');
        System.assertEquals(following.Id, carried[0].Config__c, 'It points to the new configuration');
        System.assertEquals(kept.Id, carried[0].Replaces__c, 'And to the row it continues');
        System.assert(carried[0].Reason__c.contains(setup.config.Reference__c), 'The reason says where it comes from: ' + carried[0].Reason__c);
        System.assertEquals(2, targetsOf(setup.advisor.Id).size(), 'The source row is left as it is');

        // The table of the configuration still to come shows the target it will start with
        CommissionDto.TargetTable table;
        System.runAs(setup.head) {
            table = CommissionTargetService.table(setup.project.Id, following.Reference__c);
        }
        System.assertEquals(2, table.configs.size(), 'The current and the next configuration can be chosen');
        System.assertEquals(following.Reference__c, table.reference, 'The one asked for is shown');
        assertNumber(14, rowOf(table, setup.advisor.Id).target, 'With the carried-over target');
    }

    // ------------------------------------------------------------ my terms and the controller

    @IsTest
    static void aPayeeSeesTheirOwnTerms() {
        Scene setup = prepare('Targets Terms');
        personal(setup, setup.advisor.Id, ADVISOR, 17, Date.today().addDays(-1), null);
        Commission_Rate__c rate = [
            SELECT Current_Rate__c, Exceed_Rate__c FROM Commission_Rate__c
            WHERE Config__c = :setup.config.Id AND Designation__c = :ADVISOR AND Active__c = true LIMIT 1
        ];

        List<CommissionDto.MyTerm> ofAdvisor;
        List<CommissionDto.MyTerm> ofManager;
        Test.startTest();
        System.runAs(setup.advisor) {
            ofAdvisor = CommissionTargetController.getMyTerms();
        }
        System.runAs(setup.manager) {
            ofManager = CommissionTargetService.myTerms();
        }
        Test.stopTest();

        System.assertEquals(1, ofAdvisor.size(), 'One configuration pays the advisor');
        CommissionDto.MyTerm term = ofAdvisor[0];
        System.assertEquals('Targets Terms', term.projectName, 'The project');
        System.assertEquals(setup.config.Name, term.configName, 'The configuration');
        System.assert(term.periodText.contains(CommissionTargetService.formatDate(setup.config.End_Date__c)), 'The period: ' + term.periodText);
        System.assert(String.isNotBlank(term.designationLabel), 'The designation is named');
        assertNumber(17, term.target, 'The personal target');
        System.assertEquals(false, term.isDefault, 'Marked as personal');
        assertNumber(rate.Current_Rate__c, term.currentRate, 'The Current rate of the configuration');
        assertNumber(rate.Exceed_Rate__c, term.exceedRate, 'The Exceed rate of the configuration');
        System.assert(!term.stages.isEmpty(), 'The payout stages of the internal team');
        System.assertEquals('Initial', term.stages[0].stageType, 'Starting with the Initial stage');
        for (CommissionDto.Stage stage : term.stages) {
            System.assert(String.isBlank(stage.designation), 'Only the shared stages are listed');
        }

        System.assertEquals(1, ofManager.size(), 'The manager has terms of their own');
        System.assertEquals(true, ofManager[0].isDefault, 'On the default target');
        assertNumber(defaultTarget(setup.config.Id, MANAGER), ofManager[0].target, 'Of the configuration');
    }

    @IsTest
    static void theScreenGetsTablesAndReadableErrors() {
        Scene setup = prepare('Targets Screen');
        CommissionDto.TargetTable loaded;
        CommissionDto.TargetTable saved;
        String unreadable;
        String noReason;
        Test.startTest();
        System.runAs(setup.head) {
            loaded = CommissionTargetController.getTargets(setup.project.Id, setup.config.Reference__c);
            saved = CommissionTargetController.saveTargets(JSON.serialize(changeOf(setup, setup.advisor.Id, ADVISOR, 21, Date.today(), 'From the screen')));
            try {
                CommissionTargetController.saveTargets('not a payload');
            } catch (AuraHandledException problem) {
                unreadable = problem.getMessage();
            }
            try {
                CommissionTargetController.saveTargets(JSON.serialize(changeOf(setup, setup.advisor.Id, ADVISOR, 22, Date.today(), null)));
            } catch (AuraHandledException problem) {
                noReason = problem.getMessage();
            }
        }
        System.assertEquals(setup.config.Reference__c, loaded.reference, 'The table is loaded');
        assertNumber(21, rowOf(saved, setup.advisor.Id).target, 'A save returns the new table');
        System.assertEquals(Label.Commission_Target_Bad_Request, unreadable, 'A payload that cannot be read gets its own message');
        System.assertEquals(Label.Commission_Target_Reason_Required, noReason, 'A rule of the service reaches the screen as it is');

        String refused;
        System.runAs(CommissionTestData.outsider()) {
            try {
                CommissionTargetController.getTargets(null, null);
            } catch (AuraHandledException problem) {
                refused = problem.getMessage();
            }
        }
        Test.stopTest();
        System.assertEquals(Label.Commission_Common_No_Access, refused, 'Someone without access is told so');
    }

    @IsTest
    static void textsReadAsOnTheScreens() {
        System.assertEquals('01 Sep 2026', CommissionTargetService.formatDate(Date.newInstance(2026, 9, 1)), 'Dates as 01 Sep 2026');
        System.assertEquals('', CommissionTargetService.formatDate(null), 'No date, no text');
        System.assertEquals('10', CommissionTargetService.formatNumber(10.00), 'Whole numbers without decimals');
        System.assertEquals(Decimal.valueOf('12.5').format(), CommissionTargetService.formatNumber(12.50), 'Decimals without trailing zeros');
        System.assertEquals('', CommissionTargetService.formatNumber(null), 'No number, no text');
        System.assertEquals('It\'s 5 of ', CommissionTargetService.fill('It\'s {0} of {1}', new List<Object>{ 5, null }), 'An apostrophe is kept and a missing value is empty');
        System.assertEquals(Label.Commission_Target_Basis_Units, CommissionTargetService.basisText('Units'), 'The basis is shown by its label');
        System.assertEquals(Label.Commission_Target_Basis_Value, CommissionTargetService.basisText('Value'), 'Both values');
        System.assertEquals(Label.Commission_Target_Period_Configuration, CommissionTargetService.targetPeriodText('Configuration Period'), 'The period by its label');
        System.assertEquals(Label.Commission_Target_Period_Month, CommissionTargetService.targetPeriodText('Month'), 'Month');
        System.assertEquals(Label.Commission_Target_Period_Quarter, CommissionTargetService.targetPeriodText('Quarter'), 'Quarter');
        System.assertEquals(Label.Commission_Target_Period_Year, CommissionTargetService.targetPeriodText('Year'), 'Year');
        System.assertEquals('Other', CommissionTargetService.targetPeriodText('Other'), 'An unknown value is shown as it is');
    }
}