// The shapes exchanged between the Commission Setup screens and Apex.
// Kept in one class so that the screens, the services and the triggers all agree on them.
public without sharing class CommissionDto {

    // What the running user may do (CommissionAccess: by role and profile, from Commission Setting)
    public class Flags {
        @AuraEnabled public Boolean canConfigure;
        @AuraEnabled public Boolean canApprove;
        @AuraEnabled public Boolean canManageTargets;
        @AuraEnabled public Boolean canView;
        // Holds a role named on a designation: sees "My commission terms"
        @AuraEnabled public Boolean isPayee;
        @AuraEnabled public Id userId;
        @AuraEnabled public String userName;
    }

    public class Option {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
        public Option() {}
        public Option(String value, String label) {
            this.value = value;
            this.label = label;
        }
    }

    public class Person {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        public Person() {}
        public Person(Id id, String name) {
            this.id = id;
            this.name = name;
        }
    }

    // ------------------------------------------------------------ catalog (Commission_Designation__mdt, Commission_Trigger__mdt, Commission_Setting__mdt)

    public class Designation {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public Integer order;
        // Percent | Flat
        @AuraEnabled public String rateType;
        // Shared (follows the internal team's payout stages) | Own (has its own release) | Single (one fixed payout event)
        @AuraEnabled public String split;
        @AuraEnabled public String fixedTrigger;
        @AuraEnabled public String fixedTriggerLabel;
        // Required | Optional | None
        @AuraEnabled public String targetRule;
        // The designation whose sales count towards this one's target (a Senior Manager's team)
        @AuraEnabled public String aggregateOf;
        @AuraEnabled public String claimGate;
        @AuraEnabled public String claimLabel;
        // Manual | Auto
        @AuraEnabled public String claimMode;
        @AuraEnabled public List<String> userRoles;
    }

    public class TriggerOption {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        // Any of Initial, Mid, Final
        @AuraEnabled public List<String> stageTypes;
        @AuraEnabled public String detector;
        @AuraEnabled public String sourceField;
        // None | Percent | Tranche | Installment
        @AuraEnabled public String parameterType;
        @AuraEnabled public String parameterLabel;
        @AuraEnabled public Integer order;
        @AuraEnabled public String orderGroup;
    }

    public class Settings {
        @AuraEnabled public Boolean finalStageRequired;
        @AuraEnabled public Integer expiryNoticeDays;
        @AuraEnabled public String currencyCode;
    }

    public class Installment {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Decimal sequence;
        @AuraEnabled public Id companyId;
    }

    public class Catalog {
        @AuraEnabled public List<Designation> designations;
        @AuraEnabled public List<TriggerOption> triggers;
        @AuraEnabled public Settings settings;
        // Every Payment Schedule Master row; a screen offers those of the project's company
        @AuraEnabled public List<Installment> installments;
        @AuraEnabled public List<Option> targetBases;
        @AuraEnabled public List<Option> targetPeriods;
        @AuraEnabled public List<Option> exceedModes;
    }

    // ------------------------------------------------------------ one configuration

    public class Stage {
        @AuraEnabled public Id id;
        // Row key of the screen (the record id, or a temporary key for a row not saved yet); validation issues name it
        @AuraEnabled public String key;
        // Initial | Mid | Final
        @AuraEnabled public String stageType;
        @AuraEnabled public Integer sequence;
        @AuraEnabled public String triggerKey;
        @AuraEnabled public String triggerLabel;
        @AuraEnabled public String parameterType;
        @AuraEnabled public Decimal triggerPercent;
        @AuraEnabled public Integer triggerTranche;
        @AuraEnabled public Id installmentId;
        @AuraEnabled public String installmentName;
        // 80 means 80 %
        @AuraEnabled public Decimal releasePercent;
        // Blank: a stage shared by the internal team. A designation key: that designation's own release.
        @AuraEnabled public String designation;
    }

    public class Rate {
        @AuraEnabled public Id id;
        @AuraEnabled public String key;
        @AuraEnabled public String designation;
        @AuraEnabled public String label;
        // false: the designation is not paid on this configuration
        @AuraEnabled public Boolean paid;
        @AuraEnabled public String rateType;
        // 10 means 10 %
        @AuraEnabled public Decimal currentRate;
        @AuraEnabled public Decimal exceedRate;
        @AuraEnabled public Decimal flatAmount;
        @AuraEnabled public Decimal target;
        // Units | Value
        @AuraEnabled public String targetBasis;
        @AuraEnabled public String targetPeriod;
        // Marginal (sales above target only) | Retrospective (all sales in the period)
        @AuraEnabled public String exceedMode;
        @AuraEnabled public String split;
        // All At Initial | Split (designations with their own release)
        @AuraEnabled public String releaseMode;
        @AuraEnabled public String contractReference;
        @AuraEnabled public String targetRule;
        @AuraEnabled public String claimLabel;
        @AuraEnabled public String aggregateOf;
    }

    public class Summary {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String reference;
        @AuraEnabled public Integer version;
        @AuraEnabled public Id projectId;
        @AuraEnabled public String projectName;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
        @AuraEnabled public String status;
        // DRAFT | RETURNED | PENDING | UPCOMING | ACTIVE | EXPIRED | REPLACED
        @AuraEnabled public String state;
        @AuraEnabled public String stateLabel;
        @AuraEnabled public String changeType;
        @AuraEnabled public Datetime submittedOn;
        @AuraEnabled public String submittedByName;
        @AuraEnabled public String approverName;
        @AuraEnabled public String lastModifiedByName;
        @AuraEnabled public Datetime lastModified;
    }

    public class Config {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String reference;
        @AuraEnabled public Integer version;
        @AuraEnabled public Id projectId;
        @AuraEnabled public String projectName;
        @AuraEnabled public Id companyId;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
        @AuraEnabled public Date originalEndDate;
        // Draft | Pending Approval | Approved | Superseded
        @AuraEnabled public String status;
        @AuraEnabled public String state;
        @AuraEnabled public String stateLabel;
        // New | Correction | Change From Date | Next Period | End Early | Copy
        @AuraEnabled public String changeType;
        @AuraEnabled public String changeReason;
        @AuraEnabled public Boolean carryOverTargets;
        @AuraEnabled public Boolean priceExcludesTax;
        @AuraEnabled public Id supersedesId;
        @AuraEnabled public String supersedesName;
        @AuraEnabled public Id supersededById;
        @AuraEnabled public String supersededByName;
        @AuraEnabled public Id approverId;
        @AuraEnabled public String approverName;
        @AuraEnabled public Id submittedById;
        @AuraEnabled public String submittedByName;
        @AuraEnabled public Datetime submittedOn;
        @AuraEnabled public String approvedByName;
        @AuraEnabled public Datetime approvedOn;
        // Rejected | Recalled | blank
        @AuraEnabled public String decision;
        @AuraEnabled public String decisionComments;
        @AuraEnabled public String decisionByName;
        @AuraEnabled public Datetime decisionOn;
        // What the screen loaded; a save sends it back so that a newer change by someone else is not overwritten
        @AuraEnabled public Datetime lastModified;
        @AuraEnabled public List<Stage> stages;
        @AuraEnabled public List<Rate> rates;

        // For the running user
        @AuraEnabled public Boolean canEdit;
        @AuraEnabled public Boolean canSubmit;
        @AuraEnabled public Boolean canDiscard;
        @AuraEnabled public Boolean canWithdraw;
        @AuraEnabled public Boolean canDecide;
        // Why an approver cannot decide this one (they entered or edited it)
        @AuraEnabled public String decideBlockedReason;
        @AuraEnabled public Boolean canCreateFrom;
        @AuraEnabled public Id openDraftId;
        @AuraEnabled public String openDraftName;

        // "Applies to sales whose Initial payout event is on or after ...": what approving this version does
        @AuraEnabled public String consequence;
        // The version this one is compared with: the one it replaces, else the previous approved period of the project
        @AuraEnabled public Config baseline;
        // SUPERSEDES | PREVIOUS_PERIOD | blank
        @AuraEnabled public String baselineKind;
        // The other configurations of the project (for the overlap hint)
        @AuraEnabled public List<Summary> siblings;
        // Who can approve it (Finance picks one when there are several)
        @AuraEnabled public List<Person> approvers;
    }

    public class Issue {
        // period | stages | rates | own:<designation key> | fee:<designation key> | options | general
        @AuraEnabled public String section;
        @AuraEnabled public String rowKey;
        @AuraEnabled public String field;
        @AuraEnabled public String code;
        @AuraEnabled public String message;
        public Issue() {}
        public Issue(String section, String rowKey, String field, String code, String message) {
            this.section = section;
            this.rowKey = rowKey;
            this.field = field;
            this.code = code;
            this.message = message;
        }
    }

    public class SaveResult {
        @AuraEnabled public Config config;
        @AuraEnabled public List<Issue> issues;
        @AuraEnabled public Boolean saved;
        @AuraEnabled public Boolean submitted;
    }

    // ------------------------------------------------------------ overview

    public class ProjectRow {
        @AuraEnabled public Id projectId;
        @AuraEnabled public String projectName;
        @AuraEnabled public Id companyId;
        // The approved configuration in force today
        @AuraEnabled public Summary current;
        // What comes next: a pending or draft version, or an approved configuration that starts later
        @AuraEnabled public Summary next;
        @AuraEnabled public Integer daysLeft;
        // ACTIVE | ENDING | PENDING | RETURNED | DRAFT | NO_CONFIG
        @AuraEnabled public String state;
        @AuraEnabled public String stateLabel;
        // green | amber | red | blue | grey
        @AuraEnabled public String tone;
        @AuraEnabled public String nextText;
        @AuraEnabled public Boolean nextIsWarning;
        // OPEN | NEXT_PERIOD | OPEN_DRAFT | VIEW | REVIEW | CONFIGURE | NONE
        @AuraEnabled public String action;
        @AuraEnabled public String actionLabel;
        @AuraEnabled public Boolean actionPrimary;
        @AuraEnabled public Id actionConfigId;
        @AuraEnabled public Boolean needsMyAction;
        @AuraEnabled public Boolean endingSoon;
        @AuraEnabled public Boolean noConfiguration;
        @AuraEnabled public Boolean withApprover;
        @AuraEnabled public Boolean hasDraft;
    }

    public class Workspace {
        @AuraEnabled public Flags flags;
        @AuraEnabled public Catalog catalog;
        @AuraEnabled public List<ProjectRow> projects;
        // Configurations waiting for a decision (the Approvals view)
        @AuraEnabled public List<Summary> approvals;
        @AuraEnabled public Date today;
    }

    // ------------------------------------------------------------ targets

    public class TargetRow {
        @AuraEnabled public Id userId;
        @AuraEnabled public String name;
        @AuraEnabled public String designation;
        @AuraEnabled public String designationLabel;
        // The target in force: the personal one, else the default of the configuration
        @AuraEnabled public Decimal target;
        @AuraEnabled public Boolean isDefault;
        @AuraEnabled public Decimal defaultTarget;
        @AuraEnabled public Date fromDate;
        @AuraEnabled public Date setOn;
        @AuraEnabled public String setByName;
        @AuraEnabled public String reason;
        @AuraEnabled public Decimal currentRate;
        @AuraEnabled public Decimal exceedRate;
        // Filled by the calculation phase; null until then
        @AuraEnabled public Decimal actual;
        @AuraEnabled public String result;
        @AuraEnabled public String resultTone;
        @AuraEnabled public Boolean isManager;
        @AuraEnabled public Integer teamSize;
        @AuraEnabled public Boolean canEdit;
    }

    public class TargetGroup {
        @AuraEnabled public TargetRow manager;
        @AuraEnabled public List<TargetRow> members;
    }

    public class TargetTable {
        @AuraEnabled public Id projectId;
        @AuraEnabled public String projectName;
        @AuraEnabled public String reference;
        @AuraEnabled public Id configId;
        @AuraEnabled public String configLabel;
        @AuraEnabled public String basisLabel;
        @AuraEnabled public String periodLabel;
        @AuraEnabled public Boolean canEdit;
        // People under a manager whose target counts the team's sales
        @AuraEnabled public List<TargetGroup> groups;
        // People with a target who have no such manager in the table
        @AuraEnabled public List<TargetRow> others;
        // Why the table is empty (no approved configuration, nobody in the reporting line)
        @AuraEnabled public String message;
        @AuraEnabled public List<Option> projects;
        // The approved configurations of the project: value = reference, label = "CC-0003 · 01 Sep 2026 – 31 Aug 2027"
        @AuraEnabled public List<Option> configs;
    }

    public class TargetChange {
        @AuraEnabled public Id userId;
        @AuraEnabled public String designation;
        // null: back to the default of the configuration
        @AuraEnabled public Decimal target;
    }

    public class TargetSave {
        @AuraEnabled public Id projectId;
        @AuraEnabled public String reference;
        @AuraEnabled public Date effectiveFrom;
        @AuraEnabled public String reason;
        @AuraEnabled public List<TargetChange> changes;
    }

    public class MyTerm {
        @AuraEnabled public String projectName;
        @AuraEnabled public String configName;
        @AuraEnabled public String periodText;
        @AuraEnabled public String designationLabel;
        @AuraEnabled public String rateType;
        @AuraEnabled public Decimal target;
        @AuraEnabled public Boolean isDefault;
        @AuraEnabled public String basisLabel;
        @AuraEnabled public Decimal currentRate;
        @AuraEnabled public Decimal exceedRate;
        @AuraEnabled public Decimal flatAmount;
        @AuraEnabled public String claimLabel;
        @AuraEnabled public List<Stage> stages;
    }

    // An error the screen shows as it is
    public static AuraHandledException error(String message) {
        AuraHandledException problem = new AuraHandledException(message);
        problem.setMessage(message);
        return problem;
    }
}