// The catalog behind Commission Setup: who can be paid (Commission_Designation__mdt), the payout events
// (Commission_Trigger__mdt) and the settings (Commission_Setting__mdt, record Default).
// Every other Commission class reads the custom metadata through this class, so nothing is hard-coded elsewhere.
public without sharing class CommissionCatalog {
    // Messages this class shows or sends
    @TestVisible private static final String COMMISSION_EXCEED_MODE_MARGINAL = 'Sales above target only';
    @TestVisible private static final String COMMISSION_EXCEED_MODE_RETROSPECTIVE = 'All sales in the period';
    @TestVisible private static final String COMMISSION_TARGET_BASIS_UNITS = 'Units';
    @TestVisible private static final String COMMISSION_TARGET_BASIS_VALUE = 'Value';
    @TestVisible private static final String COMMISSION_TARGET_PERIOD_CONFIGURATION = 'Configuration period';
    @TestVisible private static final String COMMISSION_TARGET_PERIOD_MONTH = 'Month';
    @TestVisible private static final String COMMISSION_TARGET_PERIOD_QUARTER = 'Quarter';
    @TestVisible private static final String COMMISSION_TARGET_PERIOD_YEAR = 'Year';


    public static final String SETTING_NAME = 'Default';

    // Tests inject their own catalog through these three
    @TestVisible static Commission_Setting__mdt testSetting;
    @TestVisible static List<Commission_Designation__mdt> testDesignations;
    @TestVisible static List<Commission_Trigger__mdt> testTriggers;

    // Read once per transaction
    private static Commission_Setting__mdt cachedSetting;
    private static List<CommissionDto.Designation> cachedDesignations;
    private static List<CommissionDto.TriggerOption> cachedTriggers;

    // The record Default; a blank in-memory record when it is missing (never null)
    public static Commission_Setting__mdt setting() {
        if (testSetting != null) {
            return testSetting;
        }
        if (cachedSetting == null) {
            List<Commission_Setting__mdt> found = [
                SELECT DeveloperName, MasterLabel,
                       Configure_Roles__c, Configure_Profiles__c, Approve_Roles__c, Approve_Profiles__c,
                       Target_Roles__c, Target_Profiles__c, View_Roles__c, View_Profiles__c, Alert_Roles__c,
                       Self_Approval_Profiles__c, Final_Stage_Required__c, Expiry_Notice_Days__c, Digest_Weekday__c,
                       Approval_Process__c, Notification_Type__c, Job_Worker_Class__c, Target_Periods__c,
                       Currency_Code__c, Email_Enabled__c
                FROM Commission_Setting__mdt
                WHERE DeveloperName = :SETTING_NAME
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            cachedSetting = found.isEmpty() ? new Commission_Setting__mdt() : found[0];
        }
        return cachedSetting;
    }

    // Active designations, by Order__c
    public static List<CommissionDto.Designation> designations() {
        // An injected catalog is read again every time: a test may replace it between two calls
        if (testDesignations != null) {
            return designationsOf(testDesignations);
        }
        if (cachedDesignations == null) {
            cachedDesignations = designationsOf([
                SELECT DeveloperName, MasterLabel, Order__c, Rate_Type__c, Split__c, Fixed_Trigger__c, Target_Rule__c,
                       Aggregate_Of__c, Claim_Gate__c, Claim_Gate_Label__c, Claim_Mode__c, User_Roles__c, Active__c
                FROM Commission_Designation__mdt
                WITH SYSTEM_MODE
                ORDER BY Order__c, DeveloperName
            ]);
        }
        return cachedDesignations;
    }

    public static Map<String, CommissionDto.Designation> designationByKey() {
        Map<String, CommissionDto.Designation> byKey = new Map<String, CommissionDto.Designation>();
        for (CommissionDto.Designation designation : designations()) {
            byKey.put(designation.key, designation);
        }
        return byKey;
    }

    // Active payout events, by Order__c
    public static List<CommissionDto.TriggerOption> triggers() {
        if (testTriggers != null) {
            return triggersOf(testTriggers);
        }
        if (cachedTriggers == null) {
            cachedTriggers = triggersOf([
                SELECT DeveloperName, MasterLabel, Stage_Types__c, Detector__c, Source_Field__c, Parameter_Type__c,
                       Parameter_Label__c, Order__c, Order_Group__c, Active__c
                FROM Commission_Trigger__mdt
                WITH SYSTEM_MODE
                ORDER BY Order__c, DeveloperName
            ]);
        }
        return cachedTriggers;
    }

    public static Map<String, CommissionDto.TriggerOption> triggerByKey() {
        Map<String, CommissionDto.TriggerOption> byKey = new Map<String, CommissionDto.TriggerOption>();
        for (CommissionDto.TriggerOption option : triggers()) {
            byKey.put(option.key, option);
        }
        return byKey;
    }

    // Everything a screen needs to build its inputs: designations, payout events, settings,
    // every Payment Schedule Master row and the option lists with their labels.
    public static CommissionDto.Catalog forScreen() {
        Commission_Setting__mdt record = setting();
        CommissionDto.Catalog catalog = new CommissionDto.Catalog();
        catalog.designations = designations();
        catalog.triggers = triggers();

        catalog.settings = new CommissionDto.Settings();
        catalog.settings.finalStageRequired = record.Final_Stage_Required__c == true;
        catalog.settings.expiryNoticeDays = record.Expiry_Notice_Days__c == null ? null : record.Expiry_Notice_Days__c.intValue();
        catalog.settings.currencyCode = record.Currency_Code__c;

        catalog.installments = new List<CommissionDto.Installment>();
        for (Payment_Schedule_Master__c row : [
            SELECT Id, Name, Installment_Sequence__c, Company__c
            FROM Payment_Schedule_Master__c
            WITH SYSTEM_MODE
            ORDER BY Company__c, Installment_Sequence__c, Name
            LIMIT 2000
        ]) {
            CommissionDto.Installment installment = new CommissionDto.Installment();
            installment.id = row.Id;
            installment.name = row.Name;
            installment.sequence = row.Installment_Sequence__c;
            installment.companyId = row.Company__c;
            catalog.installments.add(installment);
        }

        catalog.targetBases = targetBasisOptions();
        catalog.targetPeriods = targetPeriodOptions();
        catalog.exceedModes = exceedModeOptions();
        return catalog;
    }

    // 'A, b; C ' -> {'a', 'b', 'c'}: the role and profile lists of the setting
    public static Set<String> listOf(String text) {
        Set<String> values = new Set<String>();
        if (String.isBlank(text)) {
            return values;
        }
        for (String part : text.split('[,;]')) {
            if (String.isNotBlank(part)) {
                values.add(part.trim().toLowerCase());
            }
        }
        return values;
    }

    // ------------------------------------------------------------ option lists (value = what is stored, label = what is shown)

    public static List<CommissionDto.Option> targetBasisOptions() {
        return new List<CommissionDto.Option>{
            new CommissionDto.Option('Units', COMMISSION_TARGET_BASIS_UNITS),
            new CommissionDto.Option('Value', COMMISSION_TARGET_BASIS_VALUE)
        };
    }

    // Only the periods named in the setting are offered; a blank setting offers all of them
    public static List<CommissionDto.Option> targetPeriodOptions() {
        List<CommissionDto.Option> every = new List<CommissionDto.Option>{
            new CommissionDto.Option('Configuration Period', COMMISSION_TARGET_PERIOD_CONFIGURATION),
            new CommissionDto.Option('Month', COMMISSION_TARGET_PERIOD_MONTH),
            new CommissionDto.Option('Quarter', COMMISSION_TARGET_PERIOD_QUARTER),
            new CommissionDto.Option('Year', COMMISSION_TARGET_PERIOD_YEAR)
        };
        Set<String> offered = listOf(setting().Target_Periods__c);
        if (offered.isEmpty()) {
            return every;
        }
        List<CommissionDto.Option> options = new List<CommissionDto.Option>();
        for (CommissionDto.Option option : every) {
            if (offered.contains(option.value.toLowerCase())) {
                options.add(option);
            }
        }
        return options;
    }

    public static List<CommissionDto.Option> exceedModeOptions() {
        return new List<CommissionDto.Option>{
            new CommissionDto.Option('Marginal', COMMISSION_EXCEED_MODE_MARGINAL),
            new CommissionDto.Option('Retrospective', COMMISSION_EXCEED_MODE_RETROSPECTIVE)
        };
    }

    // The label of a stored option value ('Units' -> "Units"); the value itself when it is not an option
    public static String optionLabel(List<CommissionDto.Option> options, String value) {
        for (CommissionDto.Option option : options) {
            if (option.value == value) {
                return option.label;
            }
        }
        return value;
    }

    // ------------------------------------------------------------ custom metadata -> shapes of CommissionDto

    private static List<CommissionDto.Designation> designationsOf(List<Commission_Designation__mdt> records) {
        // The label of a fixed payout event (a referral fee paid on SPA signing) comes from the active events
        Map<String, CommissionDto.TriggerOption> events = triggerByKey();
        List<CommissionDto.Designation> designations = new List<CommissionDto.Designation>();
        for (Commission_Designation__mdt record : records) {
            if (record.Active__c == false) {
                continue;
            }
            CommissionDto.Designation designation = new CommissionDto.Designation();
            designation.key = record.DeveloperName;
            designation.label = String.isBlank(record.MasterLabel) ? record.DeveloperName : record.MasterLabel;
            designation.order = record.Order__c == null ? null : record.Order__c.intValue();
            designation.rateType = record.Rate_Type__c;
            designation.split = record.Split__c;
            designation.fixedTrigger = record.Fixed_Trigger__c;
            CommissionDto.TriggerOption fixedEvent = String.isBlank(record.Fixed_Trigger__c) ? null : events.get(record.Fixed_Trigger__c);
            designation.fixedTriggerLabel = fixedEvent == null ? null : fixedEvent.label;
            designation.targetRule = record.Target_Rule__c;
            designation.aggregateOf = record.Aggregate_Of__c;
            designation.claimGate = record.Claim_Gate__c;
            designation.claimLabel = record.Claim_Gate_Label__c;
            designation.claimMode = record.Claim_Mode__c;
            // Lower case, as CommissionAccess compares role names
            designation.userRoles = new List<String>(listOf(record.User_Roles__c));
            designations.add(designation);
        }
        designations.sort(new DesignationOrder());
        return designations;
    }

    private static List<CommissionDto.TriggerOption> triggersOf(List<Commission_Trigger__mdt> records) {
        List<CommissionDto.TriggerOption> options = new List<CommissionDto.TriggerOption>();
        for (Commission_Trigger__mdt record : records) {
            if (record.Active__c == false) {
                continue;
            }
            CommissionDto.TriggerOption option = new CommissionDto.TriggerOption();
            option.key = record.DeveloperName;
            option.label = String.isBlank(record.MasterLabel) ? record.DeveloperName : record.MasterLabel;
            option.stageTypes = new List<String>();
            if (String.isNotBlank(record.Stage_Types__c)) {
                for (String part : record.Stage_Types__c.split('[,;]')) {
                    if (String.isNotBlank(part)) {
                        option.stageTypes.add(part.trim());
                    }
                }
            }
            option.detector = record.Detector__c;
            option.sourceField = record.Source_Field__c;
            option.parameterType = String.isBlank(record.Parameter_Type__c) ? 'None' : record.Parameter_Type__c;
            option.parameterLabel = record.Parameter_Label__c;
            option.order = record.Order__c == null ? null : record.Order__c.intValue();
            option.orderGroup = record.Order_Group__c;
            options.add(option);
        }
        options.sort(new TriggerOrder());
        return options;
    }

    // Injected records are not sorted by a query, so both lists are sorted here: by Order, then by key
    private class DesignationOrder implements System.Comparator<CommissionDto.Designation> {
        public Integer compare(CommissionDto.Designation one, CommissionDto.Designation other) {
            Integer byOrder = compareOrder(one.order, other.order);
            return byOrder != 0 ? byOrder : textOf(one.key).compareTo(textOf(other.key));
        }
    }

    private class TriggerOrder implements System.Comparator<CommissionDto.TriggerOption> {
        public Integer compare(CommissionDto.TriggerOption one, CommissionDto.TriggerOption other) {
            Integer byOrder = compareOrder(one.order, other.order);
            return byOrder != 0 ? byOrder : textOf(one.key).compareTo(textOf(other.key));
        }
    }

    private static String textOf(String value) {
        return value == null ? '' : value;
    }

    // A record without an order comes last
    private static Integer compareOrder(Integer one, Integer other) {
        if (one == other) {
            return 0;
        }
        if (one == null) {
            return 1;
        }
        if (other == null) {
            return -1;
        }
        return one < other ? -1 : 1;
    }
}