// Every rule a commission configuration must meet, in one place.
// The save service checks what the screen sends (check), the trigger checks the saved records when a
// configuration is submitted (checkRecords): both run the same code, so the two can never disagree.
public without sharing class CommissionConfigValidator {

    // The structural values the rules branch on (picklist values and copies of the catalog kinds)
    public static final String DRAFT = 'Draft', PENDING = 'Pending Approval', APPROVED = 'Approved', SUPERSEDED = 'Superseded',
        REJECTED = 'Rejected', RECALLED = 'Recalled';
    public static final String STAGE_INITIAL = 'Initial', STAGE_MID = 'Mid', STAGE_FINAL = 'Final';
    public static final String CHANGE_NEW = 'New', CHANGE_CORRECTION = 'Correction', CHANGE_FROM_DATE = 'Change From Date',
        CHANGE_NEXT_PERIOD = 'Next Period', CHANGE_END_EARLY = 'End Early', CHANGE_COPY = 'Copy';
    public static final String RATE_PERCENT = 'Percent', RATE_FLAT = 'Flat';
    public static final String SPLIT_SHARED = 'Shared', SPLIT_OWN = 'Own', SPLIT_SINGLE = 'Single';
    public static final String RELEASE_ALL_AT_INITIAL = 'All At Initial', RELEASE_SPLIT = 'Split';
    public static final String PARAMETER_NONE = 'None', PARAMETER_PERCENT = 'Percent', PARAMETER_TRANCHE = 'Tranche',
        PARAMETER_INSTALLMENT = 'Installment';
    public static final String RULE_REQUIRED = 'Required', RULE_OPTIONAL = 'Optional', RULE_NONE = 'None';

    // Sections of the screen an issue belongs to
    public static final String SECTION_PERIOD = 'period', SECTION_STAGES = 'stages', SECTION_RATES = 'rates',
        SECTION_OWN = 'own:', SECTION_FEE = 'fee:', SECTION_OPTIONS = 'options', SECTION_GENERAL = 'general';

    // Configurations in these statuses block the same days of a project
    private static final Set<String> CLASHING = new Set<String>{ APPROVED, PENDING };

    // One payout stage, whether it came from the screen or from a record
    private class StageRow {
        public String key;
        public Id recordId;
        public String stageType;
        public Decimal sequence;
        public String triggerKey;
        public String parameterType;
        public Decimal triggerPercent;
        public Decimal triggerTranche;
        public Id installmentId;
        public Decimal releasePercent;
        public String designation;
        // "Initial", "Mid 2", "Final (CP External)": how the messages call the row
        public String name;
        public Integer position;
    }

    // One paid designation
    private class RateRow {
        public String key;
        public String designation;
        public String label;
        public String rateType;
        public String split;
        public String targetRule;
        public String releaseMode;
        public Decimal currentRate;
        public Decimal exceedRate;
        public Decimal flatAmount;
        public Decimal target;
        public String targetBasis;
        public String targetPeriod;
        public String exceedMode;
    }

    // ------------------------------------------------------------ entry points

    // What the screen sent. rowKey of an issue = the key of the stage or rate on the screen.
    public static List<CommissionDto.Issue> check(CommissionDto.Config config, Boolean forSubmit) {
        if (config == null) {
            return new List<CommissionDto.Issue>();
        }
        List<String> stageKeys = new List<String>();
        List<Commission_Stage__c> stages = mapStages(config, stageKeys);
        List<StageRow> stageRows = new List<StageRow>();
        for (Integer i = 0; i < stages.size(); i++) {
            stageRows.add(wrapStage(stages[i], stageKeys[i]));
        }
        List<String> rateKeys = new List<String>();
        List<Commission_Rate__c> rates = mapRates(config, rateKeys);
        List<RateRow> rateRows = new List<RateRow>();
        for (Integer i = 0; i < rates.size(); i++) {
            rateRows.add(wrapRate(rates[i], rateKeys[i]));
        }
        return run(headerOf(config), stageRows, rateRows, forSubmit == true);
    }

    // Saved (or in-memory) records. rowKey of an issue = the record Id. Only active rows count.
    public static List<CommissionDto.Issue> checkRecords(Commission_Config__c header, List<Commission_Stage__c> stages,
                                                         List<Commission_Rate__c> rates, Boolean forSubmit) {
        List<StageRow> stageRows = new List<StageRow>();
        Integer index = 0;
        if (stages != null) {
            for (Commission_Stage__c record : stages) {
                index++;
                if (record != null && !switchedOff(record)) {
                    stageRows.add(wrapStage(record, record.Id == null ? 'stage-' + index : String.valueOf(record.Id)));
                }
            }
        }
        List<RateRow> rateRows = new List<RateRow>();
        index = 0;
        if (rates != null) {
            for (Commission_Rate__c record : rates) {
                index++;
                if (record != null && !switchedOff(record)) {
                    rateRows.add(wrapRate(record, record.Id == null ? 'rate-' + index : String.valueOf(record.Id)));
                }
            }
        }
        return run(header == null ? new Commission_Config__c() : header, stageRows, rateRows, forSubmit == true);
    }

    // The first configuration of the same project that shares a day with this one, or null.
    // Ignored: the record itself, the version it corrects, shortens or changes from a date, and replaced versions.
    public static CommissionDto.Summary overlapWith(Commission_Config__c header) {
        if (header == null) {
            return null;
        }
        Map<String, Object> known = header.getPopulatedFieldsAsMap();
        Id projectId = (Id) known.get('Project__c');
        Date startDate = (Date) known.get('Start_Date__c');
        Date endDate = (Date) known.get('End_Date__c');
        if (projectId == null || startDate == null || endDate == null || endDate < startDate) {
            return null;
        }
        Id ownId = header.Id;
        Id ignoredId = replacesItsSource((String) known.get('Change_Type__c')) ? (Id) known.get('Supersedes__c') : null;
        for (Commission_Config__c other : [
            SELECT Id, Name, Reference__c, Version__c, Project__c, Project__r.Name, Start_Date__c, End_Date__c, Status__c,
                   Decision__c, Change_Type__c, Superseded_By__c, Submitted_On__c, Submitted_By__r.Name, Approver__r.Name,
                   LastModifiedBy.Name, LastModifiedDate
            FROM Commission_Config__c
            WHERE Project__c = :projectId AND Status__c IN :CLASHING
              AND Start_Date__c <= :endDate AND End_Date__c >= :startDate
            WITH SYSTEM_MODE
            ORDER BY Start_Date__c, Name
            LIMIT 50
        ]) {
            if (other.Id != ownId && other.Id != ignoredId) {
                return summaryOf(other);
            }
        }
        return null;
    }

    // "The period overlaps CC-0002 version 1 (01 Jan 2026 – 31 Dec 2026)."
    public static String overlapMessage(CommissionDto.Summary clash) {
        if (clash == null) {
            return null;
        }
        return fill(System.Label.Commission_Rule_Period_Overlap, new List<Object>{
            clash.name, clash.version, CommissionFormat.dateText(clash.startDate), CommissionFormat.dateText(clash.endDate)
        });
    }

    // ------------------------------------------------------------ the screen shape as records (also used to build test data)

    public static Commission_Config__c headerOf(CommissionDto.Config config) {
        Commission_Config__c header = new Commission_Config__c();
        if (config.id != null) {
            header.Id = config.id;
        }
        header.Project__c = config.projectId;
        header.Start_Date__c = config.startDate;
        header.End_Date__c = config.endDate;
        header.Status__c = String.isBlank(config.status) ? DRAFT : config.status;
        header.Reference__c = config.reference;
        header.Version__c = config.version == null ? 1 : config.version;
        header.Change_Type__c = String.isBlank(config.changeType) ? CHANGE_NEW : config.changeType;
        header.Change_Reason__c = config.changeReason;
        header.Carry_Over_Targets__c = config.carryOverTargets == true;
        header.Price_Excludes_Tax__c = config.priceExcludesTax == true;
        header.Supersedes__c = config.supersedesId;
        header.Approver__c = config.approverId;
        return header;
    }

    // The stage rows a save keeps: the shared stages, the own release of every paid designation
    // (one Initial row at 100 when everything is released at the Initial event) and the single fixed stage of a flat fee.
    public static List<Commission_Stage__c> stagesOf(CommissionDto.Config config) {
        return mapStages(config, new List<String>());
    }

    // One rate row per designation that is paid
    public static List<Commission_Rate__c> ratesOf(CommissionDto.Config config) {
        return mapRates(config, new List<String>());
    }

    private static List<Commission_Stage__c> mapStages(CommissionDto.Config config, List<String> keys) {
        Map<String, CommissionDto.Designation> designations = CommissionCatalog.designationByKey();
        Map<String, CommissionDto.TriggerOption> events = CommissionCatalog.triggerByKey();
        Map<String, CommissionDto.Rate> paid = new Map<String, CommissionDto.Rate>();
        if (config.rates != null) {
            for (CommissionDto.Rate rate : config.rates) {
                if (rate != null && rate.paid != false && String.isNotBlank(rate.designation) && !paid.containsKey(rate.designation)) {
                    paid.put(rate.designation, rate);
                }
            }
        }
        List<Commission_Stage__c> records = new List<Commission_Stage__c>();
        Set<String> withRows = new Set<String>();
        Integer index = 0;
        if (config.stages != null) {
            for (CommissionDto.Stage stage : config.stages) {
                index++;
                if (stage == null) {
                    continue;
                }
                String owner = String.isBlank(stage.designation) ? null : stage.designation;
                Decimal release = stage.releasePercent;
                if (owner != null) {
                    CommissionDto.Rate rate = paid.get(owner);
                    // A designation that is not paid keeps no release rows
                    if (rate == null) {
                        continue;
                    }
                    if (rate.releaseMode == RELEASE_ALL_AT_INITIAL) {
                        if (stage.stageType != STAGE_INITIAL) {
                            continue;
                        }
                        release = 100;
                    }
                    withRows.add(owner);
                }
                CommissionDto.TriggerOption event = String.isBlank(stage.triggerKey) ? null : events.get(stage.triggerKey);
                Commission_Stage__c record = new Commission_Stage__c();
                if (stage.id != null) {
                    record.Id = stage.id;
                }
                record.Stage_Type__c = stage.stageType;
                record.Sequence__c = stage.sequence == null ? index : stage.sequence;
                record.Trigger__c = String.isBlank(stage.triggerKey) ? null : stage.triggerKey;
                record.Trigger_Label__c = event == null ? stage.triggerLabel : event.label;
                record.Detector__c = event == null ? null : event.detector;
                record.Parameter_Type__c = event == null ? stage.parameterType : event.parameterType;
                record.Trigger_Percent__c = stage.triggerPercent;
                record.Trigger_Tranche__c = stage.triggerTranche;
                record.Trigger_Installment__c = stage.installmentId;
                record.Release_Percent__c = release;
                record.Designation__c = owner;
                record.Active__c = true;
                records.add(record);
                keys.add(String.isNotBlank(stage.key) ? stage.key : (stage.id != null ? String.valueOf(stage.id) : 'stage-' + index));
            }
        }
        // A designation with one fixed payout event (a referral fee) has its stage written by the save, not by the screen
        for (String key : paid.keySet()) {
            CommissionDto.Designation designation = designations.get(key);
            if (designation == null || designation.split != SPLIT_SINGLE || String.isBlank(designation.fixedTrigger) || withRows.contains(key)) {
                continue;
            }
            CommissionDto.TriggerOption event = events.get(designation.fixedTrigger);
            Commission_Stage__c record = new Commission_Stage__c();
            record.Stage_Type__c = STAGE_INITIAL;
            record.Sequence__c = 1;
            record.Trigger__c = designation.fixedTrigger;
            record.Trigger_Label__c = event == null ? designation.fixedTriggerLabel : event.label;
            record.Detector__c = event == null ? null : event.detector;
            record.Parameter_Type__c = event == null ? PARAMETER_NONE : event.parameterType;
            record.Release_Percent__c = 100;
            record.Designation__c = key;
            record.Active__c = true;
            records.add(record);
            keys.add('single:' + key);
        }
        return records;
    }

    private static List<Commission_Rate__c> mapRates(CommissionDto.Config config, List<String> keys) {
        Map<String, CommissionDto.Designation> designations = CommissionCatalog.designationByKey();
        List<Commission_Rate__c> records = new List<Commission_Rate__c>();
        Integer index = 0;
        if (config.rates != null) {
            for (CommissionDto.Rate rate : config.rates) {
                index++;
                // paid = false: the designation is not paid on this configuration and has no row
                if (rate == null || rate.paid == false) {
                    continue;
                }
                CommissionDto.Designation designation = String.isBlank(rate.designation) ? null : designations.get(rate.designation);
                Commission_Rate__c record = new Commission_Rate__c();
                if (rate.id != null) {
                    record.Id = rate.id;
                }
                record.Designation__c = rate.designation;
                // The catalog is the template of a draft; what the screen sent only fills in for a designation no longer in it
                record.Designation_Label__c = designation == null ? rate.label : designation.label;
                record.Rate_Type__c = designation == null ? rate.rateType : designation.rateType;
                record.Split__c = designation == null ? rate.split : designation.split;
                record.Target_Rule__c = designation == null ? rate.targetRule : designation.targetRule;
                record.Aggregate_Of__c = designation == null ? rate.aggregateOf : designation.aggregateOf;
                record.Claim_Gate__c = designation == null ? null : designation.claimGate;
                record.Claim_Gate_Label__c = designation == null ? rate.claimLabel : designation.claimLabel;
                record.Claim_Mode__c = designation == null ? null : designation.claimMode;
                record.Current_Rate__c = rate.currentRate;
                record.Exceed_Rate__c = rate.exceedRate;
                record.Flat_Amount__c = rate.flatAmount;
                record.Target__c = rate.target;
                record.Target_Basis__c = rate.targetBasis;
                record.Target_Period__c = rate.targetPeriod;
                record.Exceed_Mode__c = rate.exceedMode;
                record.Release_Mode__c = rate.releaseMode;
                record.Contract_Reference__c = rate.contractReference;
                record.Active__c = true;
                records.add(record);
                keys.add(String.isNotBlank(rate.key) ? rate.key : (rate.id != null ? String.valueOf(rate.id) : 'rate-' + index));
            }
        }
        return records;
    }

    // ------------------------------------------------------------ names

    // "Initial", "Mid 2", "Final"; with the designation for a designation's own release: "Initial (CP External)"
    public static String stageName(String stageType, Integer midNumber, String designationKey) {
        String name;
        if (stageType == STAGE_INITIAL) {
            name = System.Label.Commission_Stage_Initial;
        } else if (stageType == STAGE_FINAL) {
            name = System.Label.Commission_Stage_Final;
        } else if (stageType == STAGE_MID) {
            name = midNumber == null
                ? System.Label.Commission_Stage_Mid
                : fill(System.Label.Commission_Stage_Mid_Numbered, new List<Object>{ midNumber });
        } else {
            name = String.isBlank(stageType) ? System.Label.Commission_Rule_Stage_Unnamed : stageType;
        }
        if (String.isBlank(designationKey)) {
            return name;
        }
        return fill(System.Label.Commission_Rule_Stage_Of, new List<Object>{ name, designationLabel(designationKey) });
    }

    public static String designationLabel(String designationKey) {
        CommissionDto.Designation designation = CommissionCatalog.designationByKey().get(designationKey);
        return designation == null ? designationKey : designation.label;
    }

    // A label with its {0}, {1} filled in. Numbers and dates are turned into text first, so 1000 never becomes "1,000".
    public static String fill(String template, List<Object> values) {
        if (template == null) {
            return null;
        }
        List<String> texts = new List<String>();
        if (values != null) {
            for (Object value : values) {
                String valueText = CommissionFormat.text(value);
                texts.add(valueText == null ? '' : valueText);
            }
        }
        // String.format reads a single apostrophe as the start of quoted text and would leave {0} unfilled after it
        return String.format(template.replace('\'', '\'\''), texts);
    }

    // ------------------------------------------------------------ the rules

    private static List<CommissionDto.Issue> run(Commission_Config__c header, List<StageRow> stages, List<RateRow> rates, Boolean forSubmit) {
        List<CommissionDto.Issue> issues = new List<CommissionDto.Issue>();
        Map<String, Object> known = header.getPopulatedFieldsAsMap();

        checkPeriod(header, known, issues);

        // The first row of a designation is the one that counts
        Map<String, RateRow> paid = new Map<String, RateRow>();
        for (RateRow rate : rates) {
            if (String.isBlank(rate.designation)) {
                continue;
            }
            if (!paid.containsKey(rate.designation)) {
                paid.put(rate.designation, rate);
            } else if (forSubmit) {
                issues.add(new CommissionDto.Issue(SECTION_RATES, rate.key, 'paid', 'RATE_DUPLICATE',
                    fill(System.Label.Commission_Rule_Rate_Duplicate, new List<Object>{ rate.label })));
            }
        }
        checkStages(stages, paid, forSubmit, issues);
        checkRates(rates, forSubmit, issues);

        String changeType = (String) known.get('Change_Type__c');
        if (forSubmit && String.isNotBlank(changeType) && changeType != CHANGE_NEW && String.isBlank((String) known.get('Change_Reason__c'))) {
            issues.add(new CommissionDto.Issue(SECTION_OPTIONS, null, 'changeReason', 'REASON_REQUIRED', System.Label.Commission_Rule_Reason_Required));
        }

        // A change cannot reach back before today: the approver could only refuse it. The trigger checks once more
        // at approval, for a request that waited past its date.
        if (forSubmit) {
            Date today = Date.today();
            Date startDate = (Date) known.get('Start_Date__c');
            Date endDate = (Date) known.get('End_Date__c');
            if (changeType == CHANGE_FROM_DATE && startDate != null && startDate < today) {
                issues.add(new CommissionDto.Issue(SECTION_PERIOD, null, 'startDate', 'PERIOD_SOURCE',
                    fill(System.Label.Commission_Rule_Start_In_Past, new List<Object>{ startDate })));
            }
            if (changeType == CHANGE_END_EARLY && endDate != null && endDate < today) {
                issues.add(new CommissionDto.Issue(SECTION_PERIOD, null, 'endDate', 'PERIOD_SOURCE',
                    fill(System.Label.Commission_Rule_End_In_Past, new List<Object>{ endDate })));
            }
        }
        return issues;
    }

    private static void checkPeriod(Commission_Config__c header, Map<String, Object> known, List<CommissionDto.Issue> issues) {
        Id projectId = (Id) known.get('Project__c');
        Date startDate = (Date) known.get('Start_Date__c');
        Date endDate = (Date) known.get('End_Date__c');
        Boolean usable = true;
        if (projectId == null) {
            issues.add(new CommissionDto.Issue(SECTION_PERIOD, null, 'projectId', 'PERIOD_REQUIRED', System.Label.Commission_Rule_Project_Required));
            usable = false;
        }
        if (startDate == null) {
            issues.add(new CommissionDto.Issue(SECTION_PERIOD, null, 'startDate', 'PERIOD_REQUIRED', System.Label.Commission_Rule_Start_Required));
            usable = false;
        }
        if (endDate == null) {
            issues.add(new CommissionDto.Issue(SECTION_PERIOD, null, 'endDate', 'PERIOD_REQUIRED', System.Label.Commission_Rule_End_Required));
            usable = false;
        }
        if (startDate != null && endDate != null && endDate < startDate) {
            issues.add(new CommissionDto.Issue(SECTION_PERIOD, null, 'endDate', 'PERIOD_ORDER', System.Label.Commission_Rule_Period_Order));
            usable = false;
        }
        if (!usable) {
            return;
        }

        CommissionDto.Summary clash = overlapWith(header);
        if (clash != null) {
            issues.add(new CommissionDto.Issue(SECTION_PERIOD, null, 'startDate', 'PERIOD_OVERLAP', overlapMessage(clash)));
        }

        // The period must fit the version it was made from
        String changeType = (String) known.get('Change_Type__c');
        Id supersedesId = (Id) known.get('Supersedes__c');
        if ((changeType == CHANGE_FROM_DATE || changeType == CHANGE_END_EARLY) && supersedesId != null) {
            List<Commission_Config__c> sources = [
                SELECT Id, Name, Start_Date__c, End_Date__c
                FROM Commission_Config__c
                WHERE Id = :supersedesId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (sources.isEmpty()) {
                return;
            }
            Commission_Config__c source = sources[0];
            if (changeType == CHANGE_FROM_DATE && (startDate <= source.Start_Date__c || startDate > source.End_Date__c)) {
                issues.add(new CommissionDto.Issue(SECTION_PERIOD, null, 'startDate', 'PERIOD_SOURCE',
                    fill(System.Label.Commission_Rule_Source_Change_From, new List<Object>{ source.Start_Date__c, source.End_Date__c })));
            }
            if (changeType == CHANGE_END_EARLY && endDate > source.End_Date__c) {
                issues.add(new CommissionDto.Issue(SECTION_PERIOD, null, 'endDate', 'PERIOD_SOURCE',
                    fill(System.Label.Commission_Rule_Source_End_Early, new List<Object>{ source.End_Date__c })));
            }
        } else if (changeType == CHANGE_NEXT_PERIOD) {
            // A next period follows an approved period of the project
            Id ownId = header.Id;
            List<Commission_Config__c> earlier = [
                SELECT Id
                FROM Commission_Config__c
                WHERE Project__c = :projectId AND Status__c = :APPROVED AND End_Date__c < :startDate AND Id != :ownId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (earlier.isEmpty()) {
                issues.add(new CommissionDto.Issue(SECTION_PERIOD, null, 'startDate', 'PERIOD_SOURCE', System.Label.Commission_Rule_Source_Next_Period));
            }
        }
    }

    private static void checkStages(List<StageRow> stages, Map<String, RateRow> paid, Boolean forSubmit, List<CommissionDto.Issue> issues) {
        Map<String, CommissionDto.TriggerOption> events = CommissionCatalog.triggerByKey();
        Commission_Setting__mdt setting = CommissionCatalog.setting();

        // A payout event that has left the catalog stays valid on a row that already used it
        Set<Id> savedIds = new Set<Id>();
        for (StageRow stage : stages) {
            if (stage.recordId != null) {
                savedIds.add(stage.recordId);
            }
        }
        Map<Id, Commission_Stage__c> saved = savedIds.isEmpty()
            ? new Map<Id, Commission_Stage__c>()
            : new Map<Id, Commission_Stage__c>([SELECT Id, Trigger__c FROM Commission_Stage__c WHERE Id IN :savedIds WITH SYSTEM_MODE]);

        // The rows by owner: '' = the stages shared by the internal team, else a designation's own release
        Map<String, List<StageRow>> groups = new Map<String, List<StageRow>>();
        groups.put('', new List<StageRow>());
        Integer position = 0;
        for (StageRow stage : stages) {
            stage.position = position++;
            String owner = String.isBlank(stage.designation) ? '' : stage.designation;
            // Rows of a designation that is not paid do not count
            if (owner != '' && !paid.containsKey(owner)) {
                continue;
            }
            if (!groups.containsKey(owner)) {
                groups.put(owner, new List<StageRow>());
            }
            groups.get(owner).add(stage);
        }

        for (String owner : groups.keySet()) {
            List<StageRow> rows = groups.get(owner);
            rows.sort(new StageOrder());
            RateRow rate = owner == '' ? null : paid.get(owner);
            String section = owner == '' ? SECTION_STAGES : (rate.split == SPLIT_OWN ? SECTION_OWN + owner : SECTION_FEE + owner);

            Integer mids = 0;
            for (StageRow stage : rows) {
                if (stage.stageType == STAGE_MID) {
                    mids++;
                }
                stage.name = stageName(stage.stageType, stage.stageType == STAGE_MID ? mids : null, owner == '' ? null : owner);
            }

            Integer initials = 0;
            Integer finals = 0;
            Decimal total = 0;
            Map<String, Decimal> lastInGroup = new Map<String, Decimal>();
            for (StageRow stage : rows) {
                CommissionDto.TriggerOption event = String.isBlank(stage.triggerKey) ? null : events.get(stage.triggerKey);
                String parameterType = event != null ? event.parameterType : stage.parameterType;

                if (String.isNotBlank(stage.triggerKey)) {
                    if (event == null) {
                        Commission_Stage__c stored = stage.recordId == null ? null : saved.get(stage.recordId);
                        if (stored == null || stored.Trigger__c != stage.triggerKey) {
                            issues.add(new CommissionDto.Issue(section, stage.key, 'triggerKey', 'STAGE_TRIGGER_INVALID',
                                fill(System.Label.Commission_Rule_Stage_Trigger_Invalid, new List<Object>{ stage.name })));
                        }
                    } else if (String.isNotBlank(stage.stageType) && !event.stageTypes.contains(stage.stageType)) {
                        issues.add(new CommissionDto.Issue(section, stage.key, 'triggerKey', 'STAGE_TRIGGER_INVALID',
                            fill(System.Label.Commission_Rule_Stage_Trigger_Type, new List<Object>{ stage.name, event.label })));
                    }
                } else if (forSubmit) {
                    issues.add(new CommissionDto.Issue(section, stage.key, 'triggerKey', 'STAGE_TRIGGER_REQUIRED',
                        fill(System.Label.Commission_Rule_Stage_Trigger_Required, new List<Object>{ stage.name })));
                }

                // A parameter is only looked at when the payout event uses it
                Boolean usesPercent = String.isBlank(parameterType) || parameterType == PARAMETER_PERCENT;
                Boolean usesTranche = String.isBlank(parameterType) || parameterType == PARAMETER_TRANCHE;
                if (stage.releasePercent != null && (stage.releasePercent <= 0 || stage.releasePercent > 100)) {
                    issues.add(new CommissionDto.Issue(section, stage.key, 'releasePercent', 'STAGE_PERCENT_RANGE',
                        fill(System.Label.Commission_Rule_Stage_Percent_Range, new List<Object>{ stage.name })));
                }
                if (usesPercent && stage.triggerPercent != null && (stage.triggerPercent <= 0 || stage.triggerPercent > 100)) {
                    issues.add(new CommissionDto.Issue(section, stage.key, 'triggerPercent', 'STAGE_PERCENT_RANGE',
                        fill(System.Label.Commission_Rule_Trigger_Percent_Range, new List<Object>{ stage.name })));
                }
                if (usesTranche && stage.triggerTranche != null && stage.triggerTranche < 1) {
                    issues.add(new CommissionDto.Issue(section, stage.key, 'triggerTranche', 'STAGE_PERCENT_RANGE',
                        fill(System.Label.Commission_Rule_Tranche_Range, new List<Object>{ stage.name })));
                }

                if (stage.stageType == STAGE_INITIAL) {
                    initials++;
                    if (initials > 1) {
                        issues.add(new CommissionDto.Issue(section, stage.key, 'stageType', 'STAGE_DUPLICATE',
                            fill(System.Label.Commission_Rule_Stage_Duplicate, new List<Object>{ System.Label.Commission_Stage_Initial })));
                    }
                } else if (stage.stageType == STAGE_FINAL) {
                    finals++;
                    if (finals > 1) {
                        issues.add(new CommissionDto.Issue(section, stage.key, 'stageType', 'STAGE_DUPLICATE',
                            fill(System.Label.Commission_Rule_Stage_Duplicate, new List<Object>{ System.Label.Commission_Stage_Final })));
                    }
                } else if (stage.stageType == STAGE_MID && owner != '') {
                    issues.add(new CommissionDto.Issue(section, stage.key, 'stageType', 'STAGE_MID_NOT_ALLOWED',
                        fill(System.Label.Commission_Rule_Stage_Mid_Not_Allowed, new List<Object>{ designationLabel(owner) })));
                }
                total += stage.releasePercent == null ? 0 : stage.releasePercent;

                if (!forSubmit) {
                    continue;
                }
                if (event != null) {
                    if (parameterType == PARAMETER_PERCENT && stage.triggerPercent == null) {
                        issues.add(new CommissionDto.Issue(section, stage.key, 'triggerPercent', 'STAGE_PARAMETER_REQUIRED',
                            fill(System.Label.Commission_Rule_Parameter_Percent, new List<Object>{ stage.name })));
                    } else if (parameterType == PARAMETER_TRANCHE && stage.triggerTranche == null) {
                        issues.add(new CommissionDto.Issue(section, stage.key, 'triggerTranche', 'STAGE_PARAMETER_REQUIRED',
                            fill(System.Label.Commission_Rule_Parameter_Tranche, new List<Object>{ stage.name })));
                    } else if (parameterType == PARAMETER_INSTALLMENT && stage.installmentId == null) {
                        issues.add(new CommissionDto.Issue(section, stage.key, 'installmentId', 'STAGE_PARAMETER_REQUIRED',
                            fill(System.Label.Commission_Rule_Parameter_Installment, new List<Object>{ stage.name })));
                    }
                }
                if (stage.releasePercent == null) {
                    issues.add(new CommissionDto.Issue(section, stage.key, 'releasePercent', 'STAGE_PERCENT_REQUIRED',
                        fill(System.Label.Commission_Rule_Stage_Percent_Required, new List<Object>{ stage.name })));
                }

                // Mid payouts of one kind (% paid, tranche number) must rise from one to the next
                if (owner == '' && stage.stageType == STAGE_MID && event != null && String.isNotBlank(event.orderGroup)) {
                    Decimal value = parameterType == PARAMETER_PERCENT ? stage.triggerPercent
                        : (parameterType == PARAMETER_TRANCHE ? stage.triggerTranche : null);
                    if (value != null) {
                        Decimal previous = lastInGroup.get(event.orderGroup);
                        if (previous != null && value <= previous) {
                            issues.add(new CommissionDto.Issue(section, stage.key,
                                parameterType == PARAMETER_PERCENT ? 'triggerPercent' : 'triggerTranche', 'STAGE_MID_ORDER',
                                fill(System.Label.Commission_Rule_Mid_Order, new List<Object>{ stage.name })));
                        }
                        lastInGroup.put(event.orderGroup, value);
                    }
                }
            }

            if (!forSubmit) {
                continue;
            }
            if (owner == '') {
                if (initials == 0) {
                    issues.add(new CommissionDto.Issue(section, null, 'stageType', 'STAGE_INITIAL_REQUIRED', System.Label.Commission_Rule_Initial_Required));
                }
                if (finals == 0 && setting.Final_Stage_Required__c == true) {
                    issues.add(new CommissionDto.Issue(section, null, 'stageType', 'STAGE_FINAL_REQUIRED', System.Label.Commission_Rule_Final_Required));
                }
                if (!rows.isEmpty() && total != 100) {
                    issues.add(new CommissionDto.Issue(section, null, 'releasePercent', 'STAGES_TOTAL',
                        fill(System.Label.Commission_Rule_Stages_Total, new List<Object>{ total })));
                }
            } else if (rate.split == SPLIT_OWN && !rows.isEmpty() && total != 100) {
                // Missing rows of an own release are reported with the rate below
                issues.add(new CommissionDto.Issue(section, null, 'releasePercent', 'OWN_TOTAL',
                    fill(System.Label.Commission_Rule_Own_Total, new List<Object>{ designationLabel(owner), total })));
            }
        }

        if (!forSubmit) {
            return;
        }
        // A paid designation with its own release: the way it is released must be chosen and its rows must be there
        for (RateRow rate : paid.values()) {
            if (rate.split != SPLIT_OWN) {
                continue;
            }
            String section = SECTION_OWN + rate.designation;
            Boolean hasInitial = false;
            Boolean hasFinal = false;
            if (groups.containsKey(rate.designation)) {
                for (StageRow stage : groups.get(rate.designation)) {
                    hasInitial = hasInitial || stage.stageType == STAGE_INITIAL;
                    hasFinal = hasFinal || stage.stageType == STAGE_FINAL;
                }
            }
            if (String.isBlank(rate.releaseMode)) {
                issues.add(new CommissionDto.Issue(section, rate.key, 'releaseMode', 'OWN_RELEASE_REQUIRED',
                    fill(System.Label.Commission_Rule_Own_Mode_Required, new List<Object>{ rate.label })));
            } else if (rate.releaseMode == RELEASE_ALL_AT_INITIAL) {
                if (!hasInitial) {
                    issues.add(new CommissionDto.Issue(section, rate.key, 'triggerKey', 'OWN_RELEASE_REQUIRED',
                        fill(System.Label.Commission_Rule_Own_Initial_Required, new List<Object>{ rate.label })));
                }
            } else if (!hasInitial || !hasFinal) {
                issues.add(new CommissionDto.Issue(section, rate.key, 'releaseMode', 'OWN_RELEASE_REQUIRED',
                    fill(System.Label.Commission_Rule_Own_Split_Required, new List<Object>{ rate.label })));
            }
        }
    }

    private static void checkRates(List<RateRow> rates, Boolean forSubmit, List<CommissionDto.Issue> issues) {
        Boolean basisMissing = false;
        Boolean periodMissing = false;
        Boolean modeMissing = false;
        for (RateRow rate : rates) {
            String section = rate.split == SPLIT_OWN ? SECTION_OWN + rate.designation
                : (rate.rateType == RATE_FLAT ? SECTION_FEE + rate.designation : SECTION_RATES);
            Boolean flat = rate.rateType == RATE_FLAT;

            if (rate.currentRate != null && (rate.currentRate < 0 || rate.currentRate > 100)) {
                issues.add(new CommissionDto.Issue(section, rate.key, 'currentRate', 'RATE_RANGE',
                    fill(System.Label.Commission_Rule_Rate_Range, new List<Object>{ rate.label })));
            }
            if (rate.exceedRate != null && (rate.exceedRate < 0 || rate.exceedRate > 100)) {
                issues.add(new CommissionDto.Issue(section, rate.key, 'exceedRate', 'RATE_RANGE',
                    fill(System.Label.Commission_Rule_Rate_Range, new List<Object>{ rate.label })));
            }
            if (rate.flatAmount != null && rate.flatAmount < 0) {
                issues.add(new CommissionDto.Issue(section, rate.key, 'flatAmount', 'RATE_RANGE',
                    fill(System.Label.Commission_Rule_Amount_Negative, new List<Object>{ rate.label })));
            }
            if (rate.target != null && rate.target < 0) {
                issues.add(new CommissionDto.Issue(section, rate.key, 'target', 'RATE_RANGE',
                    fill(System.Label.Commission_Rule_Target_Negative, new List<Object>{ rate.label })));
            }
            if (rate.currentRate != null && rate.exceedRate != null && rate.exceedRate < rate.currentRate) {
                issues.add(new CommissionDto.Issue(section, rate.key, 'exceedRate', 'EXCEED_LOWER',
                    fill(System.Label.Commission_Rule_Exceed_Lower, new List<Object>{ rate.label })));
            }

            if (!forSubmit) {
                continue;
            }
            if (flat) {
                if (rate.flatAmount == null || rate.flatAmount <= 0) {
                    issues.add(new CommissionDto.Issue(section, rate.key, 'flatAmount', 'RATE_REQUIRED',
                        fill(System.Label.Commission_Rule_Amount_Required, new List<Object>{ rate.label })));
                }
                continue;
            }
            // A Current rate of 0 % is allowed, an empty one is not
            if (rate.currentRate == null) {
                issues.add(new CommissionDto.Issue(section, rate.key, 'currentRate', 'RATE_REQUIRED',
                    fill(System.Label.Commission_Rule_Rate_Required, new List<Object>{ rate.label })));
            }
            if (rate.targetRule == RULE_NONE) {
                continue;
            }
            Boolean hasTarget = rate.target != null && rate.target > 0;
            if (rate.targetRule == RULE_REQUIRED && !hasTarget) {
                issues.add(new CommissionDto.Issue(section, rate.key, 'target', 'TARGET_REQUIRED',
                    fill(System.Label.Commission_Rule_Target_Required, new List<Object>{ rate.label })));
            }
            if (hasTarget) {
                if (rate.exceedRate == null) {
                    issues.add(new CommissionDto.Issue(section, rate.key, 'exceedRate', 'EXCEED_REQUIRED',
                        fill(System.Label.Commission_Rule_Exceed_Required, new List<Object>{ rate.label })));
                }
                basisMissing = basisMissing || String.isBlank(rate.targetBasis);
                periodMissing = periodMissing || String.isBlank(rate.targetPeriod);
                modeMissing = modeMissing || String.isBlank(rate.exceedMode);
            }
        }

        if (!forSubmit) {
            return;
        }
        if (rates.isEmpty()) {
            issues.add(new CommissionDto.Issue(SECTION_RATES, null, 'paid', 'RATES_NONE', System.Label.Commission_Rule_Rates_None));
        }
        // The three target options are one control each on the screen, so each is reported once
        if (basisMissing) {
            issues.add(new CommissionDto.Issue(SECTION_RATES, null, 'targetBasis', 'TARGET_OPTIONS_REQUIRED', System.Label.Commission_Rule_Basis_Required));
        }
        if (periodMissing) {
            issues.add(new CommissionDto.Issue(SECTION_RATES, null, 'targetPeriod', 'TARGET_OPTIONS_REQUIRED', System.Label.Commission_Rule_Period_Option_Required));
        }
        if (modeMissing) {
            issues.add(new CommissionDto.Issue(SECTION_RATES, null, 'exceedMode', 'TARGET_OPTIONS_REQUIRED', System.Label.Commission_Rule_Exceed_Mode_Required));
        }
    }

    // ------------------------------------------------------------ helpers

    // Correction, End Early and Change From Date take over days of the version they were made from
    private static Boolean replacesItsSource(String changeType) {
        return changeType == CHANGE_CORRECTION || changeType == CHANGE_END_EARLY || changeType == CHANGE_FROM_DATE;
    }

    private static Boolean switchedOff(SObject record) {
        return (Boolean) record.getPopulatedFieldsAsMap().get('Active__c') == false;
    }

    // Only the fields that were read on the record are used, so a record with a few fields does not fail
    private static StageRow wrapStage(Commission_Stage__c record, String key) {
        Map<String, Object> known = record.getPopulatedFieldsAsMap();
        StageRow stage = new StageRow();
        stage.key = key;
        stage.recordId = record.Id;
        stage.stageType = (String) known.get('Stage_Type__c');
        stage.sequence = (Decimal) known.get('Sequence__c');
        stage.triggerKey = (String) known.get('Trigger__c');
        stage.parameterType = (String) known.get('Parameter_Type__c');
        stage.triggerPercent = (Decimal) known.get('Trigger_Percent__c');
        stage.triggerTranche = (Decimal) known.get('Trigger_Tranche__c');
        stage.installmentId = (Id) known.get('Trigger_Installment__c');
        stage.releasePercent = (Decimal) known.get('Release_Percent__c');
        stage.designation = (String) known.get('Designation__c');
        return stage;
    }

    private static RateRow wrapRate(Commission_Rate__c record, String key) {
        Map<String, Object> known = record.getPopulatedFieldsAsMap();
        RateRow rate = new RateRow();
        rate.key = key;
        rate.designation = (String) known.get('Designation__c');
        // What was copied onto the row at save wins; the catalog fills in for a row that has no copy
        CommissionDto.Designation designation = String.isBlank(rate.designation) ? null : CommissionCatalog.designationByKey().get(rate.designation);
        rate.label = (String) known.get('Designation_Label__c');
        rate.rateType = (String) known.get('Rate_Type__c');
        rate.split = (String) known.get('Split__c');
        rate.targetRule = (String) known.get('Target_Rule__c');
        if (designation != null) {
            rate.label = String.isBlank(rate.label) ? designation.label : rate.label;
            rate.rateType = String.isBlank(rate.rateType) ? designation.rateType : rate.rateType;
            rate.split = String.isBlank(rate.split) ? designation.split : rate.split;
            rate.targetRule = String.isBlank(rate.targetRule) ? designation.targetRule : rate.targetRule;
        }
        if (String.isBlank(rate.label)) {
            rate.label = rate.designation;
        }
        rate.releaseMode = (String) known.get('Release_Mode__c');
        rate.currentRate = (Decimal) known.get('Current_Rate__c');
        rate.exceedRate = (Decimal) known.get('Exceed_Rate__c');
        rate.flatAmount = (Decimal) known.get('Flat_Amount__c');
        rate.target = (Decimal) known.get('Target__c');
        rate.targetBasis = (String) known.get('Target_Basis__c');
        rate.targetPeriod = (String) known.get('Target_Period__c');
        rate.exceedMode = (String) known.get('Exceed_Mode__c');
        return rate;
    }

    private static CommissionDto.Summary summaryOf(Commission_Config__c record) {
        CommissionDto.Summary summary = new CommissionDto.Summary();
        summary.id = record.Id;
        summary.name = record.Name;
        summary.reference = record.Reference__c;
        summary.version = record.Version__c == null ? null : record.Version__c.intValue();
        summary.projectId = record.Project__c;
        summary.projectName = record.Project__r == null ? null : record.Project__r.Name;
        summary.startDate = record.Start_Date__c;
        summary.endDate = record.End_Date__c;
        summary.status = record.Status__c;
        summary.state = stateOf(record);
        summary.changeType = record.Change_Type__c;
        summary.submittedOn = record.Submitted_On__c;
        summary.submittedByName = record.Submitted_By__r == null ? null : record.Submitted_By__r.Name;
        summary.approverName = record.Approver__r == null ? null : record.Approver__r.Name;
        summary.lastModifiedByName = record.LastModifiedBy == null ? null : record.LastModifiedBy.Name;
        summary.lastModified = record.LastModifiedDate;
        return summary;
    }

    // The display state of a configuration that blocks days: waiting for approval, or approved
    private static String stateOf(Commission_Config__c record) {
        if (record.Status__c == PENDING) {
            return 'PENDING';
        }
        if (record.Status__c == SUPERSEDED) {
            return 'REPLACED';
        }
        if (record.Status__c == APPROVED) {
            Date today = Date.today();
            if (record.Start_Date__c != null && today < record.Start_Date__c) {
                return 'UPCOMING';
            }
            if (record.End_Date__c != null && today > record.End_Date__c) {
                return record.Superseded_By__c == null ? 'EXPIRED' : 'REPLACED';
            }
            return 'ACTIVE';
        }
        return record.Decision__c == REJECTED ? 'RETURNED' : 'DRAFT';
    }

    // By sequence; rows without one keep the order they came in, after the others
    private class StageOrder implements System.Comparator<StageRow> {
        public Integer compare(StageRow one, StageRow other) {
            if (one.sequence != other.sequence) {
                if (one.sequence == null) {
                    return 1;
                }
                if (other.sequence == null) {
                    return -1;
                }
                return one.sequence < other.sequence ? -1 : 1;
            }
            return one.position - other.position;
        }
    }
}