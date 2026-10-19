// Personal sales targets of the people a commission configuration pays: the table of the Targets view, saving a
// change, a payee's own terms, carrying targets over to the next period, and the rules of the trigger.
// A target belongs to a configuration lineage (project + reference), not to one version, so it survives a new version.
// Rows are effective-dated and never deleted: a change closes the row in force and adds a new one.
public without sharing class CommissionTargetService {
    // Messages this class shows or sends
    @TestVisible private static final String COMMISSION_COMMON_NO_ACCESS = 'You do not have access to Commission Setup. Ask your Salesforce administrator.';
    @TestVisible private static final String COMMISSION_TARGET_BASIS_UNITS = 'Units';
    @TestVisible private static final String COMMISSION_TARGET_BASIS_VALUE = 'Value';
    @TestVisible private static final String COMMISSION_TARGET_CARRIED_OVER = 'Carried over from {0}';
    @TestVisible private static final String COMMISSION_TARGET_CHANGE = '{0} → {1}';
    @TestVisible private static final String COMMISSION_TARGET_CONFIG_MISSING = 'This configuration is no longer approved and current. Reload the page and choose a configuration.';
    @TestVisible private static final String COMMISSION_TARGET_CONFIG_OPTION = '{0} · {1} – {2}';
    @TestVisible private static final String COMMISSION_TARGET_DATES_ORDER = 'A target cannot end before it starts.';
    @TestVisible private static final String COMMISSION_TARGET_DEFAULT_VALUE = '{0} (default)';
    @TestVisible private static final String COMMISSION_TARGET_FROM_AFTER_END = 'The target cannot apply after the configuration ends on {0}.';
    @TestVisible private static final String COMMISSION_TARGET_FROM_BEFORE_START = 'The target cannot apply before the configuration starts on {0}.';
    @TestVisible private static final String COMMISSION_TARGET_FROM_REQUIRED = 'Enter the date the target applies from.';
    @TestVisible private static final String COMMISSION_TARGET_NEGATIVE = 'A target cannot be below 0.';
    @TestVisible private static final String COMMISSION_TARGET_NO_CONFIGURATION = 'No project has an approved commission configuration yet. Targets can be set once a configuration is approved.';
    @TestVisible private static final String COMMISSION_TARGET_NO_DEFAULT = 'No target (default)';
    @TestVisible private static final String COMMISSION_TARGET_NO_DELETE = 'A personal target cannot be deleted. Set the person back to the default target instead.';
    @TestVisible private static final String COMMISSION_TARGET_NO_DESIGNATION = 'No designation with a target is paid in this configuration.';
    @TestVisible private static final String COMMISSION_TARGET_NO_PEOPLE = 'Nobody holds a designation with a target in this configuration.';
    @TestVisible private static final String COMMISSION_TARGET_NO_PROJECT_CONFIGURATION = '{0} has no approved commission configuration that is active or upcoming.';
    @TestVisible private static final String COMMISSION_TARGET_NO_TEAM = 'Nobody in your reporting line has a target in this configuration.';
    @TestVisible private static final String COMMISSION_TARGET_NOT_ELIGIBLE = 'One of these people does not hold a designation with a target in this configuration. Reload the page and try again.';
    @TestVisible private static final String COMMISSION_TARGET_NOTHING_TO_SAVE = 'There is no target change to save.';
    @TestVisible private static final String COMMISSION_TARGET_ONLY_HEAD = 'Only the Head of Sales can set or change a personal target.';
    @TestVisible private static final String COMMISSION_TARGET_OUTSIDE_LINE = 'You can only set a target for people in your reporting line.';
    @TestVisible private static final String COMMISSION_TARGET_OUTSIDE_LINE_NAMED = '{0} is not in your reporting line. You can only set a target for people who report to you.';
    @TestVisible private static final String COMMISSION_TARGET_OVERLAP = 'This person already has a target for these dates.';
    @TestVisible private static final String COMMISSION_TARGET_PERIOD_CONFIGURATION = 'Configuration period';
    @TestVisible private static final String COMMISSION_TARGET_PERIOD_MONTH = 'Month';
    @TestVisible private static final String COMMISSION_TARGET_PERIOD_QUARTER = 'Quarter';
    @TestVisible private static final String COMMISSION_TARGET_PERIOD_RANGE = '{0} – {1}';
    @TestVisible private static final String COMMISSION_TARGET_PERIOD_YEAR = 'Year';
    @TestVisible private static final String COMMISSION_TARGET_REASON_LONG = 'The reason can have at most {0} characters.';
    @TestVisible private static final String COMMISSION_TARGET_REASON_REQUIRED = 'Enter a reason for the target change.';
    @TestVisible private static final String COMMISSION_TARGET_TOO_LARGE = 'The target is too large.';
    @TestVisible private static final String COMMISSION_TARGET_USE_SCREEN = 'A saved target cannot be changed here. Change it on the Targets tab of Commission Setup, so that the earlier target is kept and the person is told.';


    // Switches the trigger rules off for the system steps of this service (always set in a try/finally)
    public static Boolean bypass = false;

    private static final String STATUS_APPROVED = 'Approved';
    private static final String STATE_ACTIVE = 'ACTIVE';
    private static final String STATE_UPCOMING = 'UPCOMING';
    private static final String RULE_NONE = 'None';
    private static final String SPLIT_SHARED = 'Shared';
    private static final String STAGE_INITIAL = 'Initial';
    private static final String STAGE_FINAL = 'Final';
    private static final String BASIS_UNITS = 'Units';
    private static final String BASIS_VALUE = 'Value';
    private static final String PERIOD_CONFIGURATION = 'Configuration Period';
    private static final String PERIOD_MONTH = 'Month';
    private static final String PERIOD_QUARTER = 'Quarter';
    private static final String PERIOD_YEAR = 'Year';
    // Reason__c is Text(255), Target__c is Number(14, 2)
    private static final Integer REASON_LENGTH = 255;
    private static final Decimal MAX_TARGET = Decimal.valueOf('999999999999.99');

    // One configuration lineage of a project that is approved and in force today or still to come
    private class Lineage {
        String reference;
        // The version in force today, else the first one to come: its rates are the ones shown
        Commission_Config__c config;
        Date firstStart;
        Date lastEnd;
    }

    // A designation that is paid in the configuration (an active rate row)
    private class Paid {
        String key;
        String title;
        Commission_Rate__c rate;
        // False when the designation carries no target (target rule None)
        Boolean hasTarget = false;
        // The designation whose people report to this one and count towards its target
        String aggregateOf;
        Set<String> roles = new Set<String>();
    }

    // One person in one designation
    private class Seat {
        User person;
        Paid paid;
        String key;
        Seat(User person, Paid paid) {
            this.person = person;
            this.paid = paid;
            this.key = CommissionTargetService.seatKey(person.Id, paid.key);
        }
    }

    // ------------------------------------------------------------ the Targets view

    // Both parameters are optional: without a project the first one that has an approved configuration is shown,
    // without a reference the configuration in force today.
    public static CommissionDto.TargetTable table(Id projectId, String reference) {
        if (!CommissionAccess.can(CommissionAccess.VIEW) && !CommissionAccess.can(CommissionAccess.TARGETS)) {
            throw CommissionDto.error(COMMISSION_COMMON_NO_ACCESS);
        }
        Date today = Date.today();
        Boolean mayEdit = CommissionAccess.can(CommissionAccess.TARGETS);
        CommissionDto.TargetTable result = new CommissionDto.TargetTable();
        result.canEdit = mayEdit;
        result.groups = new List<CommissionDto.TargetGroup>();
        result.others = new List<CommissionDto.TargetRow>();
        result.projects = new List<CommissionDto.Option>();
        result.configs = new List<CommissionDto.Option>();

        // The projects that can be chosen, by name
        Map<Id, List<Commission_Config__c>> byProject = new Map<Id, List<Commission_Config__c>>();
        for (Commission_Config__c config : openConfigs(today)) {
            if (!byProject.containsKey(config.Project__c)) {
                byProject.put(config.Project__c, new List<Commission_Config__c>());
                result.projects.add(new CommissionDto.Option(String.valueOf(config.Project__c), projectNameOf(config)));
            }
            byProject.get(config.Project__c).add(config);
        }
        if (projectId == null && !result.projects.isEmpty()) {
            projectId = (Id) result.projects[0].value;
        }
        if (projectId == null) {
            result.message = COMMISSION_TARGET_NO_CONFIGURATION;
            return result;
        }
        result.projectId = projectId;
        List<Commission_Config__c> ofProject = byProject.get(projectId);
        if (ofProject == null) {
            result.projectName = projectName(projectId);
            result.message = fill(COMMISSION_TARGET_NO_PROJECT_CONFIGURATION, new List<Object>{ result.projectName });
            return result;
        }
        result.projectName = projectNameOf(ofProject[0]);

        // The configurations of the project: the one asked for, else the one in force today, else the next one
        Lineage chosen = null;
        Lineage current = null;
        List<Lineage> lineages = lineagesOf(ofProject);
        for (Lineage lineage : lineages) {
            result.configs.add(new CommissionDto.Option(lineage.reference, optionText(lineage)));
            if (String.isNotBlank(reference) && lineage.reference == reference.trim()) {
                chosen = lineage;
            }
            if (current == null && lineage.config.Start_Date__c <= today) {
                current = lineage;
            }
        }
        if (chosen == null) {
            chosen = current != null ? current : lineages[0];
        }
        result.reference = chosen.reference;
        result.configId = chosen.config.Id;
        result.configLabel = optionText(chosen);

        Map<String, Paid> paidByKey = paidIn(chosen.config.Id);
        Boolean anyTarget = false;
        for (Paid paid : paidByKey.values()) {
            if (!paid.hasTarget) {
                continue;
            }
            anyTarget = true;
            // The screen shows one basis and one period: the configuration sets the same on every designation
            if (result.basisLabel == null && String.isNotBlank(paid.rate.Target_Basis__c)) {
                result.basisLabel = basisText(paid.rate.Target_Basis__c);
            }
            if (result.periodLabel == null && String.isNotBlank(paid.rate.Target_Period__c)) {
                result.periodLabel = targetPeriodText(paid.rate.Target_Period__c);
            }
        }
        if (!anyTarget) {
            result.message = COMMISSION_TARGET_NO_DESIGNATION;
            return result;
        }
        List<Seat> seats = seatsOf(paidByKey);
        if (seats.isEmpty()) {
            result.message = COMMISSION_TARGET_NO_PEOPLE;
            return result;
        }

        // A viewer and an administrator see everybody; a Head of Sales sees the people below them
        Boolean everyone = CommissionAccess.seesEveryone();
        Set<Id> line = everyone ? new Set<Id>() : reportingLine();
        List<Seat> shown = new List<Seat>();
        Set<Id> userIds = new Set<Id>();
        for (Seat seat : seats) {
            if (everyone || line.contains(seat.person.Id)) {
                shown.add(seat);
                userIds.add(seat.person.Id);
            }
        }
        if (shown.isEmpty()) {
            result.message = COMMISSION_TARGET_NO_TEAM;
            return result;
        }

        // A configuration that has not started yet shows the targets it will start with
        Date day = chosen.config.Start_Date__c > today ? chosen.config.Start_Date__c : today;
        Map<String, Commission_Target__c> personal = inForce(projectId, chosen.reference, userIds, day);

        // Managers first: each one opens a team
        Map<Id, List<Seat>> managerSeats = new Map<Id, List<Seat>>();
        Map<String, CommissionDto.TargetGroup> teamBySeat = new Map<String, CommissionDto.TargetGroup>();
        for (Seat seat : shown) {
            if (String.isBlank(seat.paid.aggregateOf)) {
                continue;
            }
            CommissionDto.TargetGroup team = new CommissionDto.TargetGroup();
            team.manager = rowOf(seat, personal.get(seat.key), chosen.config, mayEdit);
            team.manager.isManager = true;
            team.members = new List<CommissionDto.TargetRow>();
            teamBySeat.put(seat.key, team);
            result.groups.add(team);
            if (!managerSeats.containsKey(seat.person.Id)) {
                managerSeats.put(seat.person.Id, new List<Seat>());
            }
            managerSeats.get(seat.person.Id).add(seat);
        }
        // Everybody else goes under the manager they report to, when that manager's target counts their designation
        for (Seat seat : shown) {
            if (String.isNotBlank(seat.paid.aggregateOf)) {
                continue;
            }
            CommissionDto.TargetRow row = rowOf(seat, personal.get(seat.key), chosen.config, mayEdit);
            CommissionDto.TargetGroup team = null;
            List<Seat> bosses = seat.person.ManagerId == null ? null : managerSeats.get(seat.person.ManagerId);
            if (bosses != null) {
                for (Seat boss : bosses) {
                    if (boss.paid.aggregateOf == seat.paid.key) {
                        team = teamBySeat.get(boss.key);
                        break;
                    }
                }
            }
            if (team == null) {
                result.others.add(row);
            } else {
                team.members.add(row);
            }
        }
        for (CommissionDto.TargetGroup team : result.groups) {
            team.manager.teamSize = team.members.size();
        }
        return result;
    }

    private static CommissionDto.TargetRow rowOf(Seat seat, Commission_Target__c personal, Commission_Config__c config, Boolean mayEdit) {
        CommissionDto.TargetRow row = new CommissionDto.TargetRow();
        row.userId = seat.person.Id;
        row.name = seat.person.Name;
        row.designation = seat.paid.key;
        row.designationLabel = seat.paid.title;
        row.defaultTarget = seat.paid.rate.Target__c;
        if (personal != null && !hasNoEffect(personal, row.defaultTarget)) {
            row.target = personal.Target__c;
            row.isDefault = false;
            row.fromDate = personal.Effective_From__c;
            row.setOn = personal.LastModifiedDate == null ? null : personal.LastModifiedDate.date();
            row.setByName = personal.LastModifiedBy == null ? null : personal.LastModifiedBy.Name;
            row.reason = personal.Reason__c;
        } else {
            row.target = row.defaultTarget;
            row.isDefault = true;
            row.fromDate = config.Start_Date__c;
        }
        row.currentRate = seat.paid.rate.Current_Rate__c;
        row.exceedRate = seat.paid.rate.Exceed_Rate__c;
        row.isManager = false;
        row.teamSize = 0;
        // Only people the running user is allowed to see are in the table, so a target editor may edit every row
        row.canEdit = mayEdit;
        return row;
    }

    // ------------------------------------------------------------ saving

    public static CommissionDto.TargetTable save(CommissionDto.TargetSave request) {
        CommissionAccess.require(CommissionAccess.TARGETS);
        if (request == null || request.changes == null || request.changes.isEmpty()) {
            throw CommissionDto.error(COMMISSION_TARGET_NOTHING_TO_SAVE);
        }
        String reason = request.reason == null ? '' : request.reason.trim();
        if (String.isBlank(reason)) {
            throw CommissionDto.error(COMMISSION_TARGET_REASON_REQUIRED);
        }
        if (reason.length() > REASON_LENGTH) {
            throw CommissionDto.error(fill(COMMISSION_TARGET_REASON_LONG, new List<Object>{ REASON_LENGTH }));
        }
        Date fromDay = request.effectiveFrom;
        if (fromDay == null) {
            throw CommissionDto.error(COMMISSION_TARGET_FROM_REQUIRED);
        }
        Lineage lineage = lineageOf(request.projectId, request.reference, Date.today());
        if (lineage == null) {
            throw CommissionDto.error(COMMISSION_TARGET_CONFIG_MISSING);
        }
        if (fromDay < lineage.firstStart) {
            throw CommissionDto.error(fill(COMMISSION_TARGET_FROM_BEFORE_START, new List<Object>{ formatDate(lineage.firstStart) }));
        }
        if (fromDay > lineage.lastEnd) {
            throw CommissionDto.error(fill(COMMISSION_TARGET_FROM_AFTER_END, new List<Object>{ formatDate(lineage.lastEnd) }));
        }

        // Who may have a target in this configuration, and whom the running user may edit
        Map<String, Seat> seatByKey = new Map<String, Seat>();
        for (Seat seat : seatsOf(paidIn(lineage.config.Id))) {
            seatByKey.put(seat.key, seat);
        }
        Boolean everyone = CommissionAccess.seesEveryone();
        Set<Id> line = everyone ? new Set<Id>() : reportingLine();
        // The last change of a person wins when the screen sends two
        Map<String, CommissionDto.TargetChange> wanted = new Map<String, CommissionDto.TargetChange>();
        Set<Id> userIds = new Set<Id>();
        for (CommissionDto.TargetChange change : request.changes) {
            if (change == null || change.userId == null) {
                continue;
            }
            Seat seat = seatByKey.get(seatKey(change.userId, change.designation));
            if (seat == null) {
                throw CommissionDto.error(COMMISSION_TARGET_NOT_ELIGIBLE);
            }
            if (!everyone && !line.contains(change.userId)) {
                throw CommissionDto.error(fill(COMMISSION_TARGET_OUTSIDE_LINE_NAMED, new List<Object>{ seat.person.Name }));
            }
            if (change.target != null && change.target < 0) {
                throw CommissionDto.error(COMMISSION_TARGET_NEGATIVE);
            }
            if (change.target != null && change.target > MAX_TARGET) {
                throw CommissionDto.error(COMMISSION_TARGET_TOO_LARGE);
            }
            wanted.put(seat.key, change);
            userIds.add(change.userId);
        }
        if (wanted.isEmpty()) {
            throw CommissionDto.error(COMMISSION_TARGET_NOTHING_TO_SAVE);
        }

        // Every personal row of these people in this lineage, oldest first
        Map<String, List<Commission_Target__c>> history = new Map<String, List<Commission_Target__c>>();
        for (Commission_Target__c row : [
            SELECT Id, User__c, Designation__c, Target__c, Effective_From__c, Effective_To__c, Reason__c
            FROM Commission_Target__c
            WHERE Project__c = :request.projectId AND Reference__c = :lineage.reference AND User__c IN :userIds
            WITH SYSTEM_MODE
            ORDER BY Effective_From__c
        ]) {
            String key = seatKey(row.User__c, row.Designation__c);
            if (!history.containsKey(key)) {
                history.put(key, new List<Commission_Target__c>());
            }
            history.get(key).add(row);
        }

        List<Commission_Target__c> updates = new List<Commission_Target__c>();
        List<Commission_Target__c> inserts = new List<Commission_Target__c>();
        // What the notification says about each row that carries a change
        List<Commission_Target__c> told = new List<Commission_Target__c>();
        List<String> toldText = new List<String>();

        for (String key : wanted.keySet()) {
            CommissionDto.TargetChange change = wanted.get(key);
            Seat seat = seatByKey.get(key);
            Decimal standard = seat.paid.rate.Target__c;
            Decimal asked = change.target == null ? null : change.target.setScale(2, RoundingMode.HALF_UP);

            // The row in force on the chosen day, and the first one that starts later
            Commission_Target__c current = null;
            Commission_Target__c next = null;
            List<Commission_Target__c> known = history.get(key);
            if (known != null) {
                for (Commission_Target__c row : known) {
                    if (row.Effective_From__c <= fromDay && (row.Effective_To__c == null || row.Effective_To__c >= fromDay)) {
                        current = row;
                    } else if (row.Effective_From__c > fromDay && next == null) {
                        next = row;
                    }
                }
            }
            // A row that an earlier "back to default" on its first day left without effect counts as no row
            Boolean idle = current != null && hasNoEffect(current, standard);
            Boolean isPersonal = current != null && !idle;
            String oldText = isPersonal ? formatNumber(current.Target__c) : defaultText(standard);
            Date openUntil = next == null ? null : next.Effective_From__c.addDays(-1);

            if (asked == null) {
                // Back to the default of the configuration
                if (!isPersonal) {
                    continue;
                }
                if (current.Effective_From__c == fromDay) {
                    // The row starts on the chosen day: it cannot end before it starts, so it is left without effect
                    current.Effective_To__c = current.Effective_From__c;
                    current.Target__c = standard;
                } else {
                    current.Effective_To__c = fromDay.addDays(-1);
                }
                // Either way the row says why it ended
                current.Reason__c = reason;
                updates.add(current);
                told.add(current);
                toldText.add(fill(COMMISSION_TARGET_CHANGE, new List<Object>{ oldText, defaultText(standard) }));
                continue;
            }

            if (isPersonal && current.Target__c == asked) {
                continue;
            }
            Commission_Target__c carrier;
            if (current != null && current.Effective_From__c == fromDay) {
                // The row in force starts on the chosen day: it is corrected, a second row would end before it starts
                current.Target__c = asked;
                current.Reason__c = reason;
                if (idle) {
                    current.Effective_To__c = openUntil;
                }
                updates.add(current);
                carrier = current;
            } else {
                // The new row runs until the row it replaces would have ended, or until the next row starts
                carrier = new Commission_Target__c(
                    Project__c = request.projectId,
                    Reference__c = lineage.reference,
                    Config__c = lineage.config.Id,
                    User__c = seat.person.Id,
                    Designation__c = seat.paid.key,
                    Target__c = asked,
                    Effective_From__c = fromDay,
                    Effective_To__c = current != null ? current.Effective_To__c : openUntil,
                    Reason__c = reason
                );
                if (current != null) {
                    carrier.Replaces__c = current.Id;
                    current.Effective_To__c = fromDay.addDays(-1);
                    updates.add(current);
                }
                inserts.add(carrier);
            }
            told.add(carrier);
            toldText.add(fill(COMMISSION_TARGET_CHANGE, new List<Object>{ oldText, formatNumber(asked) }));
        }

        if (!told.isEmpty()) {
            Savepoint mark = Database.setSavepoint();
            Boolean earlier = bypass;
            try {
                // The rows in force were checked above; closing and correcting them is a system step.
                // The new rows go through the trigger, which checks the overlap once more.
                bypass = true;
                try {
                    if (!updates.isEmpty()) {
                        update as system updates;
                    }
                } finally {
                    bypass = earlier;
                }
                if (!inserts.isEmpty()) {
                    insert as system inserts;
                }
            } catch (DmlException problem) {
                Database.rollback(mark);
                throw CommissionDto.error(problem.getDmlMessage(0));
            } catch (Exception problem) {
                Database.rollback(mark);
                throw problem;
            }
            Map<Id, String> changeById = new Map<Id, String>();
            for (Integer i = 0; i < told.size(); i++) {
                changeById.put(told[i].Id, toldText[i]);
            }
            CommissionNotifier.enqueueTargets(changeById, fromDay, reason);
        }
        return table(request.projectId, lineage.reference);
    }

    // ------------------------------------------------------------ a payee's own terms

    // What the running user is paid, in every configuration of an active project that is approved and in force
    // today or still to come. Someone who is not paid commission gets an empty list.
    public static List<CommissionDto.MyTerm> myTerms() {
        List<CommissionDto.MyTerm> terms = new List<CommissionDto.MyTerm>();
        Id userId = UserInfo.getUserId();
        List<User> me = [SELECT Id, UserRole.DeveloperName FROM User WHERE Id = :userId WITH SYSTEM_MODE LIMIT 1];
        if (me.isEmpty() || me[0].UserRole == null || String.isBlank(me[0].UserRole.DeveloperName)) {
            return terms;
        }
        String role = me[0].UserRole.DeveloperName.toLowerCase();
        // The designations the user's role holds, in catalog order
        List<CommissionDto.Designation> mine = new List<CommissionDto.Designation>();
        Set<String> keys = new Set<String>();
        for (CommissionDto.Designation designation : CommissionCatalog.designations()) {
            if (String.isNotBlank(designation.key) && rolesOf(designation).contains(role)) {
                mine.add(designation);
                keys.add(designation.key);
            }
        }
        if (mine.isEmpty()) {
            return terms;
        }

        Date today = Date.today();
        List<Id> configIds = new List<Id>();
        Map<Id, Map<String, Commission_Rate__c>> ratesByConfig = new Map<Id, Map<String, Commission_Rate__c>>();
        Set<String> references = new Set<String>();
        for (Commission_Rate__c rate : [
            SELECT Id, Config__c, Designation__c, Designation_Label__c, Rate_Type__c, Current_Rate__c, Exceed_Rate__c,
                Flat_Amount__c, Target__c, Target_Basis__c, Split__c, Claim_Gate_Label__c, Target_Rule__c,
                Config__r.Name, Config__r.Reference__c, Config__r.Project__c, Config__r.Project__r.Name,
                Config__r.Start_Date__c, Config__r.End_Date__c
            FROM Commission_Rate__c
            WHERE Active__c = true AND Designation__c IN :keys
                AND Config__r.Status__c = :STATUS_APPROVED AND Config__r.End_Date__c >= :today
                AND Config__r.Project__r.Active__c = true
            WITH SYSTEM_MODE
            ORDER BY Config__r.Project__r.Name, Config__r.Start_Date__c, Config__r.Name
        ]) {
            if (!ratesByConfig.containsKey(rate.Config__c)) {
                ratesByConfig.put(rate.Config__c, new Map<String, Commission_Rate__c>());
                configIds.add(rate.Config__c);
            }
            ratesByConfig.get(rate.Config__c).put(rate.Designation__c.toLowerCase(), rate);
            references.add(referenceOf(rate.Config__r));
        }
        if (configIds.isEmpty()) {
            return terms;
        }

        // The payout stages of those configurations: Initial, the Mid stages in their order, Final
        Map<Id, List<Commission_Stage__c>> stagesByConfig = new Map<Id, List<Commission_Stage__c>>();
        for (Commission_Stage__c stage : [
            SELECT Id, Config__c, Stage_Type__c, Sequence__c, Trigger__c, Trigger_Label__c, Parameter_Type__c,
                Trigger_Percent__c, Trigger_Tranche__c, Trigger_Installment__c, Installment_Name__c,
                Release_Percent__c, Designation__c
            FROM Commission_Stage__c
            WHERE Config__c IN :configIds AND Active__c = true
            WITH SYSTEM_MODE
            ORDER BY Sequence__c NULLS LAST, Name
        ]) {
            if (!stagesByConfig.containsKey(stage.Config__c)) {
                stagesByConfig.put(stage.Config__c, new List<Commission_Stage__c>());
            }
            stagesByConfig.get(stage.Config__c).add(stage);
        }

        // The user's own targets in those lineages
        List<Commission_Target__c> targets = [
            SELECT Id, Project__c, Reference__c, Designation__c, Target__c, Effective_From__c, Effective_To__c
            FROM Commission_Target__c
            WHERE User__c = :userId AND Reference__c IN :references
            WITH SYSTEM_MODE
            ORDER BY Effective_From__c
        ];

        for (Id configId : configIds) {
            for (CommissionDto.Designation designation : mine) {
                Commission_Rate__c rate = ratesByConfig.get(configId).get(designation.key.toLowerCase());
                if (rate == null) {
                    continue;
                }
                Commission_Config__c config = rate.Config__r;
                CommissionDto.MyTerm term = new CommissionDto.MyTerm();
                term.projectName = config.Project__r == null ? null : config.Project__r.Name;
                term.configName = config.Name;
                term.periodText = periodText(config.Start_Date__c, config.End_Date__c);
                term.designationLabel = String.isNotBlank(rate.Designation_Label__c) ? rate.Designation_Label__c : designation.label;
                term.rateType = rate.Rate_Type__c;
                term.currentRate = rate.Current_Rate__c;
                term.exceedRate = rate.Exceed_Rate__c;
                term.flatAmount = rate.Flat_Amount__c;
                term.basisLabel = basisText(rate.Target_Basis__c);
                term.claimLabel = String.isNotBlank(rate.Claim_Gate_Label__c) ? rate.Claim_Gate_Label__c : designation.claimLabel;
                String rule = String.isNotBlank(rate.Target_Rule__c) ? rate.Target_Rule__c : designation.targetRule;
                term.isDefault = true;
                if (rule != RULE_NONE) {
                    term.target = rate.Target__c;
                    // A configuration that has not started yet shows the target it will start with
                    Date day = config.Start_Date__c > today ? config.Start_Date__c : today;
                    for (Commission_Target__c target : targets) {
                        if (target.Project__c == config.Project__c && target.Reference__c == referenceOf(config)
                                && target.Designation__c == rate.Designation__c && coversDay(target, day)
                                && !hasNoEffect(target, rate.Target__c)) {
                            term.target = target.Target__c;
                            term.isDefault = false;
                        }
                    }
                }
                // The internal team shares the configuration's stages; other designations have their own
                String split = String.isNotBlank(rate.Split__c) ? rate.Split__c : designation.split;
                term.stages = stagesFor(stagesByConfig.get(configId), split == SPLIT_SHARED ? null : rate.Designation__c);
                terms.add(term);
            }
        }
        return terms;
    }

    private static List<CommissionDto.Stage> stagesFor(List<Commission_Stage__c> stages, String designation) {
        List<CommissionDto.Stage> initial = new List<CommissionDto.Stage>();
        List<CommissionDto.Stage> middle = new List<CommissionDto.Stage>();
        List<CommissionDto.Stage> closing = new List<CommissionDto.Stage>();
        if (stages != null) {
            for (Commission_Stage__c stage : stages) {
                Boolean wanted = String.isBlank(designation) ? String.isBlank(stage.Designation__c) : stage.Designation__c == designation;
                if (!wanted) {
                    continue;
                }
                CommissionDto.Stage row = new CommissionDto.Stage();
                row.id = stage.Id;
                row.key = stage.Id;
                row.stageType = stage.Stage_Type__c;
                row.sequence = stage.Sequence__c == null ? null : stage.Sequence__c.intValue();
                row.triggerKey = stage.Trigger__c;
                row.triggerLabel = stage.Trigger_Label__c;
                row.parameterType = stage.Parameter_Type__c;
                row.triggerPercent = stage.Trigger_Percent__c;
                row.triggerTranche = stage.Trigger_Tranche__c == null ? null : stage.Trigger_Tranche__c.intValue();
                row.installmentId = stage.Trigger_Installment__c;
                row.installmentName = stage.Installment_Name__c;
                row.releasePercent = stage.Release_Percent__c;
                row.designation = stage.Designation__c;
                if (stage.Stage_Type__c == STAGE_INITIAL) {
                    initial.add(row);
                } else if (stage.Stage_Type__c == STAGE_FINAL) {
                    closing.add(row);
                } else {
                    middle.add(row);
                }
            }
        }
        initial.addAll(middle);
        initial.addAll(closing);
        return initial;
    }

    // ------------------------------------------------------------ next period

    // Copies the personal targets still in force on the day before the new configuration starts to its lineage,
    // effective from its first day. Called at the approval of a Next Period configuration.
    public static void carryOver(String fromReference, Commission_Config__c toConfig) {
        if (String.isBlank(fromReference) || toConfig == null || toConfig.Id == null) {
            return;
        }
        // Read again: the reference of a new lineage is written after the insert
        List<Commission_Config__c> found = [
            SELECT Id, Name, Reference__c, Project__c, Start_Date__c
            FROM Commission_Config__c
            WHERE Id = :toConfig.Id
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (found.isEmpty() || found[0].Start_Date__c == null) {
            return;
        }
        Commission_Config__c config = found[0];
        String toReference = referenceOf(config);
        if (toReference == fromReference) {
            return;
        }
        Date lastDay = config.Start_Date__c.addDays(-1);

        // Nobody gets a second row when the step runs twice, or when a target was already set for the new period
        Set<String> taken = new Set<String>();
        for (Commission_Target__c row : [
            SELECT User__c, Designation__c
            FROM Commission_Target__c
            WHERE Project__c = :config.Project__c AND Reference__c = :toReference
            WITH SYSTEM_MODE
        ]) {
            taken.add(seatKey(row.User__c, row.Designation__c));
        }

        String reason = fill(COMMISSION_TARGET_CARRIED_OVER, new List<Object>{ fromReference });
        List<Commission_Target__c> copies = new List<Commission_Target__c>();
        for (Commission_Target__c source : [
            SELECT Id, User__c, Designation__c, Target__c
            FROM Commission_Target__c
            WHERE Project__c = :config.Project__c AND Reference__c = :fromReference AND Target__c != null
                AND Effective_From__c <= :lastDay AND (Effective_To__c = null OR Effective_To__c >= :lastDay)
            WITH SYSTEM_MODE
            ORDER BY Effective_From__c
        ]) {
            String key = seatKey(source.User__c, source.Designation__c);
            if (taken.contains(key)) {
                continue;
            }
            taken.add(key);
            copies.add(new Commission_Target__c(
                Project__c = config.Project__c,
                Reference__c = toReference,
                Config__c = config.Id,
                User__c = source.User__c,
                Designation__c = source.Designation__c,
                Target__c = source.Target__c,
                Effective_From__c = config.Start_Date__c,
                Reason__c = reason,
                Replaces__c = source.Id
            ));
        }
        if (copies.isEmpty()) {
            return;
        }
        Boolean earlier = bypass;
        bypass = true;
        try {
            insert as system copies;
        } finally {
            bypass = earlier;
        }
    }

    // ------------------------------------------------------------ trigger rules

    // Before insert, update and delete of Commission_Target__c. Nothing is checked while a service works under bypass.
    public static void rows(System.TriggerOperation operation, List<Commission_Target__c> newRows, Map<Id, Commission_Target__c> oldMap) {
        if (bypass || CommissionTriggerHandler.bypass) {
            return;
        }
        switch on operation {
            when BEFORE_DELETE {
                // A target row is history: it is closed, never removed
                for (Commission_Target__c row : oldMap.values()) {
                    row.addError(COMMISSION_TARGET_NO_DELETE);
                }
            }
            when BEFORE_INSERT {
                checkRows(newRows, null);
            }
            when BEFORE_UPDATE {
                checkRows(newRows, oldMap);
            }
            when else {
                return;
            }
        }
    }

    // oldMap is null at an insert
    private static void checkRows(List<Commission_Target__c> newRows, Map<Id, Commission_Target__c> oldMap) {
        if (newRows == null || newRows.isEmpty()) {
            return;
        }
        if (!CommissionAccess.can(CommissionAccess.TARGETS)) {
            for (Commission_Target__c row : newRows) {
                row.addError(COMMISSION_TARGET_ONLY_HEAD);
            }
            return;
        }
        Boolean everyone = CommissionAccess.seesEveryone();
        Set<Id> line = everyone ? new Set<Id>() : reportingLine();
        List<Commission_Target__c> sound = new List<Commission_Target__c>();
        Set<Id> userIds = new Set<Id>();
        Set<Id> ownIds = new Set<Id>();
        for (Commission_Target__c row : newRows) {
            if (row.Id != null) {
                ownIds.add(row.Id);
            }
            Commission_Target__c prior = oldMap == null ? null : oldMap.get(row.Id);
            // The person the row belonged to must be in the reporting line as well
            if (!everyone && (!line.contains(row.User__c) || (prior != null && !line.contains(prior.User__c)))) {
                row.addError(COMMISSION_TARGET_OUTSIDE_LINE);
            } else if (prior != null && (row.User__c != prior.User__c || row.Project__c != prior.Project__c
                    || row.Reference__c != prior.Reference__c || row.Designation__c != prior.Designation__c
                    || row.Effective_From__c != prior.Effective_From__c || row.Target__c != prior.Target__c)) {
                // A saved target is history: a new target is a new row, written by the Targets screen, which keeps the earlier row and tells the person
                row.addError(COMMISSION_TARGET_USE_SCREEN);
            } else if (String.isBlank(row.Reason__c)) {
                row.addError(COMMISSION_TARGET_REASON_REQUIRED);
            } else if (row.Target__c != null && row.Target__c < 0) {
                row.addError(COMMISSION_TARGET_NEGATIVE);
            } else if (row.Effective_From__c != null && row.Effective_To__c != null && row.Effective_To__c < row.Effective_From__c) {
                row.addError(COMMISSION_TARGET_DATES_ORDER);
            } else if (row.User__c != null && row.Effective_From__c != null) {
                sound.add(row);
                userIds.add(row.User__c);
            }
        }
        if (sound.isEmpty()) {
            return;
        }
        // One person, designation and lineage can only have one target on any day
        Map<String, List<Commission_Target__c>> stored = new Map<String, List<Commission_Target__c>>();
        for (Commission_Target__c row : [
            SELECT Id, User__c, Designation__c, Reference__c, Effective_From__c, Effective_To__c
            FROM Commission_Target__c
            WHERE User__c IN :userIds AND Id NOT IN :ownIds
            WITH SYSTEM_MODE
        ]) {
            String key = lineKey(row);
            if (!stored.containsKey(key)) {
                stored.put(key, new List<Commission_Target__c>());
            }
            stored.get(key).add(row);
        }
        Map<String, List<Commission_Target__c>> accepted = new Map<String, List<Commission_Target__c>>();
        for (Commission_Target__c row : sound) {
            String key = lineKey(row);
            Boolean clash = false;
            for (List<Commission_Target__c> others : new List<List<Commission_Target__c>>{ stored.get(key), accepted.get(key) }) {
                if (others == null) {
                    continue;
                }
                for (Commission_Target__c other : others) {
                    if (shareADay(row, other)) {
                        clash = true;
                        break;
                    }
                }
            }
            if (clash) {
                row.addError(COMMISSION_TARGET_OVERLAP);
                continue;
            }
            if (!accepted.containsKey(key)) {
                accepted.put(key, new List<Commission_Target__c>());
            }
            accepted.get(key).add(row);
        }
    }

    // ------------------------------------------------------------ what the three parts share

    // Approved configurations of active projects that are in force today or still to come, by project and start
    private static List<Commission_Config__c> openConfigs(Date today) {
        List<Commission_Config__c> found = new List<Commission_Config__c>();
        for (Commission_Config__c config : [
            SELECT Id, Name, Reference__c, Version__c, Project__c, Project__r.Name, Start_Date__c, End_Date__c,
                Status__c, Decision__c, Superseded_By__c, Superseded_By__r.Version__c, Submitted_On__c
            FROM Commission_Config__c
            WHERE Status__c = :STATUS_APPROVED AND End_Date__c >= :today AND Start_Date__c != null
                AND Project__r.Active__c = true
            WITH SYSTEM_MODE
            ORDER BY Project__r.Name, Start_Date__c, Version__c
        ]) {
            String state = CommissionConfigService.stateOf(config, today);
            if (state == STATE_ACTIVE || state == STATE_UPCOMING) {
                found.add(config);
            }
        }
        return found;
    }

    // The configurations of one project (ordered by start) as lineages
    private static List<Lineage> lineagesOf(List<Commission_Config__c> configs) {
        List<Lineage> lineages = new List<Lineage>();
        Map<String, Lineage> byReference = new Map<String, Lineage>();
        for (Commission_Config__c config : configs) {
            String reference = referenceOf(config);
            Lineage lineage = byReference.get(reference.toLowerCase());
            if (lineage == null) {
                // The first one by start is the version in force today, or the first one to come
                lineage = new Lineage();
                lineage.reference = reference;
                lineage.config = config;
                lineage.firstStart = config.Start_Date__c;
                lineage.lastEnd = config.End_Date__c;
                byReference.put(reference.toLowerCase(), lineage);
                lineages.add(lineage);
            } else if (config.End_Date__c > lineage.lastEnd) {
                // A later version of the same configuration (terms changed from a date)
                lineage.lastEnd = config.End_Date__c;
            }
        }
        return lineages;
    }

    private static Lineage lineageOf(Id projectId, String reference, Date today) {
        if (projectId == null || String.isBlank(reference)) {
            return null;
        }
        List<Commission_Config__c> ofProject = new List<Commission_Config__c>();
        for (Commission_Config__c config : openConfigs(today)) {
            if (config.Project__c == projectId) {
                ofProject.add(config);
            }
        }
        for (Lineage lineage : lineagesOf(ofProject)) {
            if (lineage.reference == reference.trim()) {
                return lineage;
            }
        }
        return null;
    }

    // The designations paid in a configuration, by lower-case key. The values copied onto the rate row at save
    // win over the catalog, so an approved configuration does not change when the catalog is edited.
    private static Map<String, Paid> paidIn(Id configId) {
        Map<String, CommissionDto.Designation> catalog = new Map<String, CommissionDto.Designation>();
        for (CommissionDto.Designation designation : CommissionCatalog.designations()) {
            if (String.isNotBlank(designation.key)) {
                catalog.put(designation.key.toLowerCase(), designation);
            }
        }
        Map<String, Paid> found = new Map<String, Paid>();
        for (Commission_Rate__c rate : [
            SELECT Id, Designation__c, Designation_Label__c, Rate_Type__c, Current_Rate__c, Exceed_Rate__c, Target__c,
                Target_Basis__c, Target_Period__c, Target_Rule__c, Aggregate_Of__c
            FROM Commission_Rate__c
            WHERE Config__c = :configId AND Active__c = true AND Designation__c != null
            WITH SYSTEM_MODE
            ORDER BY Name
        ]) {
            CommissionDto.Designation designation = catalog.get(rate.Designation__c.toLowerCase());
            Paid paid = new Paid();
            paid.key = rate.Designation__c;
            paid.rate = rate;
            paid.title = String.isNotBlank(rate.Designation_Label__c) ? rate.Designation_Label__c
                : (designation == null ? rate.Designation__c : designation.label);
            String rule = String.isNotBlank(rate.Target_Rule__c) ? rate.Target_Rule__c
                : (designation == null ? null : designation.targetRule);
            paid.hasTarget = rule != RULE_NONE;
            paid.aggregateOf = String.isNotBlank(rate.Aggregate_Of__c) ? rate.Aggregate_Of__c
                : (designation == null ? null : designation.aggregateOf);
            if (designation != null) {
                paid.roles = rolesOf(designation);
            }
            found.put(rate.Designation__c.toLowerCase(), paid);
        }
        return found;
    }

    // Everybody who holds a paid designation that carries a target, by name
    private static List<Seat> seatsOf(Map<String, Paid> paidByKey) {
        Map<String, List<Paid>> byRole = new Map<String, List<Paid>>();
        for (Paid paid : paidByKey.values()) {
            if (!paid.hasTarget) {
                continue;
            }
            for (String role : paid.roles) {
                if (!byRole.containsKey(role)) {
                    byRole.put(role, new List<Paid>());
                }
                byRole.get(role).add(paid);
            }
        }
        List<Seat> seats = new List<Seat>();
        for (User person : holders(byRole.keySet())) {
            List<Paid> held = person.UserRole == null || person.UserRole.DeveloperName == null
                ? null : byRole.get(person.UserRole.DeveloperName.toLowerCase());
            if (held == null) {
                continue;
            }
            for (Paid paid : held) {
                seats.add(new Seat(person, paid));
            }
        }
        return seats;
    }

    // The personal rows in force on a day, by person and designation
    private static Map<String, Commission_Target__c> inForce(Id projectId, String reference, Set<Id> userIds, Date day) {
        Map<String, Commission_Target__c> found = new Map<String, Commission_Target__c>();
        for (Commission_Target__c row : [
            SELECT Id, User__c, Designation__c, Target__c, Effective_From__c, Effective_To__c, Reason__c,
                LastModifiedDate, LastModifiedBy.Name
            FROM Commission_Target__c
            WHERE Project__c = :projectId AND Reference__c = :reference AND User__c IN :userIds
                AND Effective_From__c <= :day AND (Effective_To__c = null OR Effective_To__c >= :day)
            WITH SYSTEM_MODE
            ORDER BY Effective_From__c
        ]) {
            found.put(seatKey(row.User__c, row.Designation__c), row);
        }
        return found;
    }

    // Active internal users who hold one of these roles (UserRole.DeveloperName, any case), by name
    public static List<User> holders(Set<String> roleNames) {
        if (roleNames == null || roleNames.isEmpty()) {
            return new List<User>();
        }
        return [
            SELECT Id, Name, ManagerId, UserRoleId, UserRole.DeveloperName
            FROM User
            WHERE IsActive = true AND UserType = 'Standard' AND UserRole.DeveloperName IN :roleNames
            WITH SYSTEM_MODE
            ORDER BY Name
            LIMIT 5000
        ];
    }

    // The roles named on a designation, lower case
    public static Set<String> rolesOf(CommissionDto.Designation designation) {
        Set<String> roles = new Set<String>();
        if (designation != null && designation.userRoles != null) {
            for (String role : designation.userRoles) {
                if (String.isNotBlank(role)) {
                    roles.add(role.trim().toLowerCase());
                }
            }
        }
        return roles;
    }

    private static Set<Id> reportingLine() {
        Set<Id> line = CommissionAccess.reportingLine(UserInfo.getUserId());
        return line == null ? new Set<Id>() : line;
    }

    // The lineage of a configuration: its reference, or its own name while the reference is not written yet
    public static String referenceOf(Commission_Config__c config) {
        return String.isBlank(config.Reference__c) ? config.Name : config.Reference__c;
    }

    private static String projectNameOf(Commission_Config__c config) {
        return config.Project__r == null ? '' : config.Project__r.Name;
    }

    private static String projectName(Id projectId) {
        List<Project__c> found = [SELECT Name FROM Project__c WHERE Id = :projectId WITH SYSTEM_MODE LIMIT 1];
        return found.isEmpty() ? '' : found[0].Name;
    }

    private static String optionText(Lineage lineage) {
        return fill(COMMISSION_TARGET_CONFIG_OPTION, new List<Object>{
            lineage.reference, formatDate(lineage.firstStart), formatDate(lineage.lastEnd)
        });
    }

    private static String seatKey(Id userId, String designation) {
        return String.valueOf(userId) + '|' + (designation == null ? '' : designation.trim().toLowerCase());
    }

    private static String lineKey(Commission_Target__c row) {
        return seatKey(row.User__c, row.Designation__c) + '|' + (row.Reference__c == null ? '' : row.Reference__c.trim().toLowerCase());
    }

    public static Boolean coversDay(Commission_Target__c row, Date day) {
        return row.Effective_From__c != null && row.Effective_From__c <= day
            && (row.Effective_To__c == null || row.Effective_To__c >= day);
    }

    private static Boolean shareADay(Commission_Target__c one, Commission_Target__c other) {
        if (one.Effective_From__c == null || other.Effective_From__c == null) {
            return false;
        }
        return (other.Effective_To__c == null || one.Effective_From__c <= other.Effective_To__c)
            && (one.Effective_To__c == null || other.Effective_From__c <= one.Effective_To__c);
    }

    // A one-day row that holds the default: what "back to default" leaves of a row that started on that same day
    public static Boolean hasNoEffect(Commission_Target__c row, Decimal standard) {
        return row.Effective_To__c != null && row.Effective_To__c == row.Effective_From__c && row.Target__c == standard;
    }

    private static String defaultText(Decimal standard) {
        return standard == null ? COMMISSION_TARGET_NO_DEFAULT
            : fill(COMMISSION_TARGET_DEFAULT_VALUE, new List<Object>{ formatNumber(standard) });
    }

    // ------------------------------------------------------------ texts

    // 'Units' -> the label of the target basis
    public static String basisText(String value) {
        if (value == BASIS_UNITS) {
            return COMMISSION_TARGET_BASIS_UNITS;
        }
        if (value == BASIS_VALUE) {
            return COMMISSION_TARGET_BASIS_VALUE;
        }
        return value;
    }

    // 'Configuration Period' -> the label of the target period
    public static String targetPeriodText(String value) {
        if (value == PERIOD_CONFIGURATION) {
            return COMMISSION_TARGET_PERIOD_CONFIGURATION;
        }
        if (value == PERIOD_MONTH) {
            return COMMISSION_TARGET_PERIOD_MONTH;
        }
        if (value == PERIOD_QUARTER) {
            return COMMISSION_TARGET_PERIOD_QUARTER;
        }
        if (value == PERIOD_YEAR) {
            return COMMISSION_TARGET_PERIOD_YEAR;
        }
        return value;
    }

    // 01 Sep 2026
    public static String formatDate(Date value) {
        if (value == null) {
            return '';
        }
        return Datetime.newInstance(value.year(), value.month(), value.day()).format('dd MMM yyyy');
    }

    // 01 Sep 2026 – 31 Aug 2027
    public static String periodText(Date startDay, Date endDay) {
        return fill(COMMISSION_TARGET_PERIOD_RANGE, new List<Object>{ formatDate(startDay), formatDate(endDay) });
    }

    // 10.00 -> 10, 12.50 -> 12.5, 500000 -> 500,000
    public static String formatNumber(Decimal value) {
        if (value == null) {
            return '';
        }
        if (value == 0) {
            return '0';
        }
        Decimal plain = value.stripTrailingZeros();
        if (plain.scale() < 0) {
            plain = plain.setScale(0);
        }
        return plain.format();
    }

    // A label with {0}, {1} ... filled in. An apostrophe in the label is kept and a missing value becomes empty.
    public static String fill(String pattern, List<Object> values) {
        if (pattern == null) {
            return '';
        }
        List<Object> texts = new List<Object>();
        if (values != null) {
            for (Object value : values) {
                texts.add(value == null ? '' : String.valueOf(value));
            }
        }
        return String.format(pattern.replace('\'', '\'\''), texts);
    }
}