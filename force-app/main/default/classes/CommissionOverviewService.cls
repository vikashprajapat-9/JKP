// What the Commission Setup tab opens with: what the running user may do, the catalog, one row per active project
// with the configuration in force and what comes next, and the configurations waiting for a decision.
public without sharing class CommissionOverviewService {

    // ProjectRow.state
    public static final String ROW_ACTIVE = 'ACTIVE';
    public static final String ROW_ENDING = 'ENDING';
    public static final String ROW_PENDING = 'PENDING';
    public static final String ROW_RETURNED = 'RETURNED';
    public static final String ROW_DRAFT = 'DRAFT';
    public static final String ROW_NO_CONFIG = 'NO_CONFIG';

    // ProjectRow.action
    public static final String ACTION_OPEN = 'OPEN';
    public static final String ACTION_NEXT_PERIOD = 'NEXT_PERIOD';
    public static final String ACTION_OPEN_DRAFT = 'OPEN_DRAFT';
    public static final String ACTION_VIEW = 'VIEW';
    public static final String ACTION_REVIEW = 'REVIEW';
    public static final String ACTION_CONFIGURE = 'CONFIGURE';
    public static final String ACTION_NONE = 'NONE';

    private static final String TONE_GREEN = 'green';
    private static final String TONE_AMBER = 'amber';
    private static final String TONE_RED = 'red';
    private static final String TONE_BLUE = 'blue';
    private static final String TONE_GREY = 'grey';

    // The configurations of one project that matter for its row
    private class Situation {
        Commission_Config__c inForce;
        Commission_Config__c pending;
        Commission_Config__c draft;
        Commission_Config__c upcoming;
        // Start dates of every approved configuration: is the day after the current one covered?
        Set<Date> approvedStarts = new Set<Date>();
    }

    public static CommissionDto.Workspace workspace() {
        CommissionDto.Flags flags = CommissionAccess.flags();
        Boolean canView = CommissionAccess.can(CommissionAccess.VIEW);
        Date today = Date.today();
        CommissionDto.Workspace space = new CommissionDto.Workspace();
        space.flags = flags;
        space.today = today;
        space.projects = new List<CommissionDto.ProjectRow>();
        space.approvals = new List<CommissionDto.Summary>();
        // Somebody with no part in commission gets the flags only (all false): the tab shows its "no access" state
        if (!canView && (flags == null || flags.isPayee != true)) {
            space.catalog = emptyCatalog();
            return space;
        }
        space.catalog = CommissionCatalog.forScreen();
        // Somebody who is only paid sees their own terms, not the projects
        if (!canView) {
            return space;
        }
        Boolean canConfigure = CommissionAccess.can(CommissionAccess.CONFIGURE);
        Boolean canApprove = CommissionAccess.can(CommissionAccess.APPROVE);
        Decimal noticeSetting = CommissionCatalog.setting().Expiry_Notice_Days__c;
        Integer noticeDays = noticeSetting == null ? 0 : noticeSetting.intValue();

        List<Project__c> projects = [
            SELECT Id, Name, Company__c
            FROM Project__c
            WHERE Active__c = true
            WITH SYSTEM_MODE
            ORDER BY Name
            LIMIT 2000
        ];
        Map<Id, Situation> situations = new Map<Id, Situation>();
        for (Project__c project : projects) {
            situations.put(project.Id, new Situation());
        }

        // Every configuration that still counts, oldest first, so that "latest" and "earliest" fall out of the order
        Set<Id> projectIds = situations.keySet();
        String superseded = CommissionConfigService.STATUS_SUPERSEDED;
        List<Commission_Config__c> configs = projectIds.isEmpty() ? new List<Commission_Config__c>()
            : (List<Commission_Config__c>) Database.queryWithBinds(
                'SELECT ' + CommissionConfigService.SUMMARY_FIELDS + ' FROM Commission_Config__c'
                    + ' WHERE Project__c IN :projectIds AND Status__c != :superseded'
                    + ' ORDER BY Start_Date__c, CreatedDate, Name',
                new Map<String, Object>{ 'projectIds' => projectIds, 'superseded' => superseded },
                AccessLevel.SYSTEM_MODE
            );
        for (Commission_Config__c config : configs) {
            Situation situation = situations.get(config.Project__c);
            if (situation == null) {
                continue;
            }
            if (config.Status__c == CommissionConfigService.STATUS_APPROVED) {
                if (config.Start_Date__c != null) {
                    situation.approvedStarts.add(config.Start_Date__c);
                }
                if (config.Start_Date__c != null && config.End_Date__c != null
                        && config.Start_Date__c <= today && today <= config.End_Date__c) {
                    situation.inForce = config;
                } else if (config.Start_Date__c != null && config.Start_Date__c > today && situation.upcoming == null) {
                    situation.upcoming = config;
                }
            } else if (config.Status__c == CommissionConfigService.STATUS_PENDING) {
                if (situation.pending == null || isLater(config.Submitted_On__c, situation.pending.Submitted_On__c)) {
                    situation.pending = config;
                }
            } else if (config.Status__c == CommissionConfigService.STATUS_DRAFT) {
                if (situation.draft == null || isLater(config.CreatedDate, situation.draft.CreatedDate)) {
                    situation.draft = config;
                }
            }
        }

        for (Project__c project : projects) {
            space.projects.add(rowOf(project, situations.get(project.Id), today, noticeDays, canConfigure, canApprove));
        }

        // The Approvals view: everything that waits for a decision, also for a project that is no longer active
        String pendingStatus = CommissionConfigService.STATUS_PENDING;
        for (Commission_Config__c waiting : (List<Commission_Config__c>) Database.queryWithBinds(
            'SELECT ' + CommissionConfigService.SUMMARY_FIELDS + ' FROM Commission_Config__c'
                + ' WHERE Status__c = :pendingStatus ORDER BY Submitted_On__c DESC NULLS LAST, CreatedDate DESC LIMIT 500',
            new Map<String, Object>{ 'pendingStatus' => pendingStatus },
            AccessLevel.SYSTEM_MODE
        )) {
            space.approvals.add(CommissionConfigService.summary(waiting));
        }
        return space;
    }

    // One project's row, by the priority: waiting for approval, returned, draft, nothing in force, ending soon, active.
    private static CommissionDto.ProjectRow rowOf(Project__c project, Situation situation, Date today, Integer noticeDays,
                                                  Boolean canConfigure, Boolean canApprove) {
        CommissionDto.ProjectRow row = new CommissionDto.ProjectRow();
        row.projectId = project.Id;
        row.projectName = project.Name;
        row.companyId = project.Company__c;
        row.nextIsWarning = false;
        row.actionPrimary = false;
        row.needsMyAction = false;

        Commission_Config__c inForce = situation.inForce;
        Boolean successorApproved = false;
        if (inForce != null) {
            row.current = CommissionConfigService.summary(inForce);
            row.daysLeft = today.daysBetween(inForce.End_Date__c);
            successorApproved = situation.approvedStarts.contains(inForce.End_Date__c.addDays(1));
        }
        row.noConfiguration = inForce == null;
        row.withApprover = situation.pending != null;
        row.hasDraft = situation.draft != null;
        row.endingSoon = inForce != null && noticeDays > 0 && row.daysLeft <= noticeDays && !successorApproved;

        if (situation.pending != null) {
            // A request that sits with another approver is not this approver's to decide
            Boolean mayDecide = canApprove && CommissionConfigService.decideBlockedReason(situation.pending) == null
                && CommissionConfigService.otherApproverReason(situation.pending) == null;
            row.state = ROW_PENDING;
            row.stateLabel = CommissionConfigService.stateLabel(situation.pending, today);
            row.tone = TONE_BLUE;
            row.action = mayDecide ? ACTION_REVIEW : ACTION_VIEW;
            row.actionConfigId = situation.pending.Id;
            row.needsMyAction = mayDecide;
        } else if (situation.draft != null) {
            Boolean returned = situation.draft.Decision__c == CommissionConfigService.DECISION_REJECTED;
            row.state = returned ? ROW_RETURNED : ROW_DRAFT;
            row.stateLabel = returned ? Label.Commission_State_Returned : Label.Commission_State_Draft;
            row.tone = returned ? TONE_RED : TONE_GREY;
            // Only Finance works on a draft; everybody else looks at it
            row.action = canConfigure ? ACTION_OPEN_DRAFT : ACTION_VIEW;
            row.actionConfigId = situation.draft.Id;
            row.needsMyAction = canConfigure;
        } else if (inForce == null) {
            row.state = ROW_NO_CONFIG;
            row.stateLabel = Label.Commission_Service_No_Configuration;
            row.tone = TONE_GREY;
            if (situation.upcoming != null) {
                row.action = ACTION_OPEN;
                row.actionConfigId = situation.upcoming.Id;
            } else {
                row.action = canConfigure ? ACTION_CONFIGURE : ACTION_NONE;
                row.needsMyAction = canConfigure;
            }
        } else if (row.endingSoon) {
            row.state = ROW_ENDING;
            row.stateLabel = endingLabel(row.daysLeft);
            row.tone = TONE_AMBER;
            row.action = canConfigure ? ACTION_NEXT_PERIOD : ACTION_OPEN;
            row.actionConfigId = inForce.Id;
            row.needsMyAction = canConfigure;
        } else {
            row.state = ROW_ACTIVE;
            row.stateLabel = Label.Commission_State_Active;
            row.tone = TONE_GREEN;
            row.action = ACTION_OPEN;
            row.actionConfigId = inForce.Id;
        }
        row.actionLabel = actionLabel(row.action);
        row.actionPrimary = row.needsMyAction == true && row.action != ACTION_NONE;

        // What comes next: the version waiting or being drafted, else the approved configuration that starts later
        Commission_Config__c following = situation.pending != null ? situation.pending
            : (situation.draft != null ? situation.draft : situation.upcoming);
        if (following != null) {
            row.next = CommissionConfigService.summary(following);
            row.nextText = nextText(following, inForce);
        } else if (row.state == ROW_ENDING) {
            row.nextText = Label.Commission_Service_Next_None_Approved;
            row.nextIsWarning = true;
        } else {
            row.nextText = Label.Commission_Common_None;
        }
        return row;
    }

    // "v2: change terms from 01 Nov 2026" for a new version of the configuration in force,
    // "CC-0005 · v1 from 01 Nov 2026" for anything else; a draft says so after the version.
    private static String nextText(Commission_Config__c following, Commission_Config__c inForce) {
        Boolean isDraft = following.Status__c == CommissionConfigService.STATUS_DRAFT;
        String versionNumber = following.Version__c == null ? '' : String.valueOf(following.Version__c.intValue());
        String version = String.format(
            isDraft ? Label.Commission_Service_Next_Version_Draft : Label.Commission_Common_Version_Short,
            new List<Object>{ versionNumber }
        );
        String fromDate = CommissionConfigService.formatDate(following.Start_Date__c);
        if (inForce != null && following.Supersedes__c == inForce.Id && following.Status__c != CommissionConfigService.STATUS_APPROVED) {
            if (following.Change_Type__c == CommissionConfigService.CHANGE_CORRECTION) {
                return String.format(Label.Commission_Service_Next_Correction, new List<Object>{ version });
            }
            if (following.Change_Type__c == CommissionConfigService.CHANGE_FROM_DATE) {
                return String.format(Label.Commission_Service_Next_From_Date, new List<Object>{ version, fromDate });
            }
            if (following.Change_Type__c == CommissionConfigService.CHANGE_END_EARLY) {
                return String.format(
                    Label.Commission_Service_Next_End_Early,
                    new List<Object>{ version, CommissionConfigService.formatDate(following.End_Date__c) }
                );
            }
        }
        String reference = String.isBlank(following.Reference__c) ? following.Name : following.Reference__c;
        return String.format(Label.Commission_Service_Next_Other, new List<Object>{ reference, version, fromDate });
    }

    // Nothing of the catalog, in the shape the screens expect
    private static CommissionDto.Catalog emptyCatalog() {
        CommissionDto.Catalog catalog = new CommissionDto.Catalog();
        catalog.designations = new List<CommissionDto.Designation>();
        catalog.triggers = new List<CommissionDto.TriggerOption>();
        catalog.settings = new CommissionDto.Settings();
        catalog.installments = new List<CommissionDto.Installment>();
        catalog.targetBases = new List<CommissionDto.Option>();
        catalog.targetPeriods = new List<CommissionDto.Option>();
        catalog.exceedModes = new List<CommissionDto.Option>();
        return catalog;
    }

    private static String endingLabel(Integer daysLeft) {
        if (daysLeft == null || daysLeft <= 0) {
            return Label.Commission_Service_Ends_Today;
        }
        if (daysLeft == 1) {
            return Label.Commission_Service_Ends_Tomorrow;
        }
        return String.format(Label.Commission_Service_Ends_In_Days, new List<Object>{ String.valueOf(daysLeft) });
    }

    private static String actionLabel(String action) {
        if (action == ACTION_OPEN) {
            return Label.Commission_Service_Action_Open;
        }
        if (action == ACTION_NEXT_PERIOD) {
            return Label.Commission_Service_Action_Next_Period;
        }
        if (action == ACTION_OPEN_DRAFT) {
            return Label.Commission_Service_Action_Open_Draft;
        }
        if (action == ACTION_VIEW) {
            return Label.Commission_Service_Action_View;
        }
        if (action == ACTION_REVIEW) {
            return Label.Commission_Service_Action_Review;
        }
        if (action == ACTION_CONFIGURE) {
            return Label.Commission_Service_Action_Configure;
        }
        return null;
    }

    private static Boolean isLater(Datetime candidate, Datetime reference) {
        return candidate != null && (reference == null || candidate >= reference);
    }
}