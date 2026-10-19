// Test data shared by every Commission test class: an injected catalog (so that no test depends on the
// custom metadata records of the org), test users with their roles, and ready-made configurations.
@IsTest
public class CommissionTestData {

    public static final String ROLE_FINANCE = 'Commission_Test_Finance';
    public static final String ROLE_APPROVER = 'Commission_Test_Approver';
    public static final String ROLE_HOS = 'Commission_Test_HOS';
    public static final String ROLE_SM = 'Commission_Test_SM';
    public static final String ROLE_ADVISOR = 'Commission_Test_Advisor';
    // Held by the user without any capability (a user who owns records must keep a role)
    public static final String ROLE_OUTSIDER = 'Commission_Test_Outsider';
    public static final String PROFILE_NAME = 'Standard User';

    private static final String SEAT_FINANCE = 'finance', SEAT_SECOND_FINANCE = 'secondFinance', SEAT_APPROVER = 'approver',
        SEAT_HEAD_OF_SALES = 'headOfSales', SEAT_SENIOR_MANAGER = 'seniorManager', SEAT_ADVISOR = 'advisor', SEAT_OUTSIDER = 'outsider';
    private static final List<String> SEATS = new List<String>{
        SEAT_FINANCE, SEAT_SECOND_FINANCE, SEAT_APPROVER, SEAT_HEAD_OF_SALES, SEAT_SENIOR_MANAGER, SEAT_ADVISOR, SEAT_OUTSIDER
    };
    private static final Map<String, String> ROLE_OF_SEAT = new Map<String, String>{
        SEAT_FINANCE => ROLE_FINANCE, SEAT_SECOND_FINANCE => ROLE_FINANCE, SEAT_APPROVER => ROLE_APPROVER, SEAT_HEAD_OF_SALES => ROLE_HOS,
        SEAT_SENIOR_MANAGER => ROLE_SM, SEAT_ADVISOR => ROLE_ADVISOR, SEAT_OUTSIDER => ROLE_OUTSIDER
    };

    // The same user record every time a test asks for a seat
    private static Map<String, User> people;

    // ------------------------------------------------------------ catalog

    // Injects the 7 designations, the 9 payout events and a setting whose role lists name the test roles.
    // Every profile list is blank, so a capability is held through a test role only.
    public static void useCatalog() {
        CommissionCatalog.testSetting = (Commission_Setting__mdt) metadataRecord(Commission_Setting__mdt.class, 'Commission_Setting__mdt',
            new Map<String, Object>{
                'DeveloperName' => 'Default', 'MasterLabel' => 'Default',
                'Configure_Roles__c' => ROLE_FINANCE,
                'Approve_Roles__c' => ROLE_APPROVER,
                'Target_Roles__c' => ROLE_HOS,
                'Alert_Roles__c' => ROLE_FINANCE,
                'Final_Stage_Required__c' => true,
                'Expiry_Notice_Days__c' => 7,
                'Digest_Weekday__c' => 'Monday',
                'Approval_Process__c' => 'Commission_Config_Approval',
                'Notification_Type__c' => 'Commission_Alert',
                'Job_Worker_Class__c' => 'CommissionDailyCheck',
                'Target_Periods__c' => 'Configuration Period',
                'Currency_Code__c' => 'LKR',
                'Email_Enabled__c' => false
            });

        CommissionCatalog.testDesignations = new List<Commission_Designation__mdt>{
            designation('Sales_Advisor', 'Sales Advisor', 1, 'Percent', 'Shared', null, 'Required', null,
                'Initial_Event', 'At the Initial payout event', 'Manual', ROLE_ADVISOR),
            designation('Senior_Manager_Advisor', 'Senior Manager (Advisor)', 2, 'Percent', 'Shared', null, 'Required', 'Sales_Advisor',
                'Initial_Event', 'At the Initial payout event', 'Manual', ROLE_SM),
            designation('Customer_Service', 'Customer Service', 3, 'Percent', 'Shared', null, 'Required', null,
                'Second_Tranche_Confirmed', 'After the 2nd tranche is paid and confirmed by Finance', 'Manual', null),
            designation('Senior_Manager_CS', 'Senior Manager (CS)', 4, 'Percent', 'Shared', null, 'Required', 'Customer_Service',
                'Second_Tranche_Confirmed', 'After the 2nd tranche is paid and confirmed by Finance', 'Manual', null),
            designation('CP_Internal', 'CP Internal', 5, 'Percent', 'Shared', null, 'Optional', null,
                'Initial_Event', 'At the Initial payout event', 'Manual', null),
            designation('CP_External', 'CP External', 6, 'Percent', 'Own', null, 'Optional', null,
                'Own_Stages', 'At its own payout events', 'Manual', null),
            designation('Referrer', 'Referral fee', 7, 'Flat', 'Single', 'SPA_Signing', 'None', null,
                'Fixed_Event', 'Paid 100% on SPA signing', 'Auto', null)
        };

        CommissionCatalog.testTriggers = new List<Commission_Trigger__mdt>{
            payoutEvent('SPA_Signing', 'SPA signing date', 'Initial', 'Date_Field', 'SPA_Signed_Date__c', 'None', null, 1, null),
            payoutEvent('Booking_Deposit_Received', 'Initial booking deposit received date', 'Initial', 'Date_Field', null, 'None', null, 2, null),
            payoutEvent('Offer_Letter_Generated', 'Offer letter generated date', 'Initial', 'Date_Field', null, 'None', null, 3, null),
            payoutEvent('Offer_Letter_Signed', 'Offer letter signing date', 'Initial', 'Date_Field', null, 'None', null, 4, null),
            payoutEvent('Percent_Of_Price_Paid', '% of purchase price paid', 'Mid', 'Percent_Paid', null, 'Percent', '% paid', 5, 'PERCENT'),
            payoutEvent('Tranche_Paid', 'A tranche is paid', 'Mid', 'Tranche_Paid', null, 'Tranche', 'tranche no.', 6, 'TRANCHE'),
            payoutEvent('Installment_Paid', 'A Payment Schedule Master instalment is paid', 'Mid', 'Installment_Paid', null, 'Installment', null, 7, null),
            payoutEvent('Handover', 'Handover date', 'Final', 'Date_Field', null, 'None', null, 8, null),
            payoutEvent('Fully_Paid', '100% payment paid date', 'Final', 'Fully_Paid', null, 'None', null, 9, null)
        };
        CommissionAccess.reset();
    }

    // Changes values of the injected setting (field API name -> value), for example
    // setSetting(new Map<String, Object>{ 'Self_Approval_Profiles__c' => 'Standard User' })
    public static void setSetting(Map<String, Object> changes) {
        if (CommissionCatalog.testSetting == null) {
            useCatalog();
        }
        Map<String, Object> values = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(CommissionCatalog.testSetting));
        values.remove('attributes');
        values.putAll(changes);
        CommissionCatalog.testSetting = (Commission_Setting__mdt) metadataRecord(Commission_Setting__mdt.class, 'Commission_Setting__mdt', values);
        CommissionAccess.reset();
    }

    // ------------------------------------------------------------ records

    // An active project. Document Id is filled so that the project counts as having its SharePoint folder.
    public static Project__c project(String name) {
        Project__c created = new Project__c(
            Name = name,
            Active__c = true,
            Document_Id__c = name,
            // Required on the object
            Email__c = 'commission.test@example.com',
            Location__Latitude__s = 6.9271,
            Location__Longitude__s = 79.8612
        );
        insert created;
        return created;
    }

    // Unsaved and complete: Initial on SPA signing 80, Mid at 50 % paid 10, Final on handover 10; the five internal
    // designations paid with targets; CP External released 80 / 20; a referral fee of 500,000.
    public static CommissionDto.Config validDraft(Id projectId, Date startDate, Date endDate) {
        CommissionDto.Config config = new CommissionDto.Config();
        config.projectId = projectId;
        config.startDate = startDate;
        config.endDate = endDate;
        config.status = 'Draft';
        config.state = 'DRAFT';
        config.changeType = 'New';
        config.version = 1;
        config.carryOverTargets = false;
        config.priceExcludesTax = false;
        config.stages = new List<CommissionDto.Stage>{
            stage('stage-1', 'Initial', 1, 'SPA_Signing', null, 80, null),
            stage('stage-2', 'Mid', 2, 'Percent_Of_Price_Paid', 50, 10, null),
            stage('stage-3', 'Final', 3, 'Handover', null, 10, null),
            stage('stage-4', 'Initial', 1, 'SPA_Signing', null, 80, 'CP_External'),
            stage('stage-5', 'Final', 2, 'Handover', null, 20, 'CP_External')
        };
        CommissionDto.Rate external = rate('CP_External', 3, null, null);
        external.releaseMode = 'Split';
        external.contractReference = 'CP-TEST-001';
        CommissionDto.Rate referrer = rate('Referrer', null, null, null);
        referrer.flatAmount = 500000;
        config.rates = new List<CommissionDto.Rate>{
            rate('Sales_Advisor', 1.5, 2, 10),
            rate('Senior_Manager_Advisor', 0.5, 0.75, 30),
            rate('Customer_Service', 0.25, 0.5, 20),
            rate('Senior_Manager_CS', 0.1, 0.2, 60),
            rate('CP_Internal', 0.5, 1, 15),
            external,
            referrer
        };
        return config;
    }

    // An Approved configuration with the content of validDraft, written as a system step (no approval process).
    // The record comes back with every field.
    public static Commission_Config__c insertApproved(Id projectId, Date startDate, Date endDate) {
        CommissionDto.Config config = validDraft(projectId, startDate, endDate);
        Commission_Config__c header = CommissionConfigValidator.headerOf(config);
        header.Status__c = 'Approved';
        header.Approver__c = UserInfo.getUserId();
        header.Submitted_By__c = UserInfo.getUserId();
        header.Submitted_On__c = System.now();
        header.Approved_By__c = UserInfo.getUserId();
        header.Approved_On__c = System.now();
        Boolean bypassBefore = CommissionTriggerHandler.bypass;
        CommissionTriggerHandler.bypass = true;
        try {
            insert header;
            insertRows(header.Id, config);
        } finally {
            CommissionTriggerHandler.bypass = bypassBefore;
        }
        return record(header.Id);
    }

    // A Draft with the content of the screen shape, saved as the running user through the triggers
    // (so the running user needs the right to configure). Returns the record with every field.
    public static Commission_Config__c insertDraft(CommissionDto.Config config) {
        Commission_Config__c header = CommissionConfigValidator.headerOf(config);
        insert header;
        insertRows(header.Id, config);
        return record(header.Id);
    }

    public static Commission_Config__c record(Id configId) {
        return [
            SELECT Id, Name, OwnerId, CreatedById, CreatedDate, LastModifiedById, LastModifiedDate,
                   Project__c, Project__r.Name, Project_Name__c, Start_Date__c, End_Date__c, Original_End_Date__c,
                   Status__c, Status_Display__c, Reference__c, Version__c, Version_Key__c, Supersedes__c, Superseded_By__c,
                   Change_Type__c, Change_Reason__c, Carry_Over_Targets__c, Price_Excludes_Tax__c, Approver__c,
                   Submitted_By__c, Submitted_On__c, Approved_By__c, Approved_On__c, Decision__c, Decision_By__c,
                   Decision_On__c, Decision_Comments__c, Editor_Ids__c
            FROM Commission_Config__c
            WHERE Id = :configId
        ];
    }

    public static List<Commission_Stage__c> stagesOf(Id configId) {
        return [
            SELECT Id, Name, Config__c, Stage_Type__c, Sequence__c, Trigger__c, Trigger_Label__c, Detector__c, Parameter_Type__c,
                   Trigger_Percent__c, Trigger_Tranche__c, Trigger_Installment__c, Release_Percent__c, Designation__c, Active__c
            FROM Commission_Stage__c
            WHERE Config__c = :configId
            ORDER BY Designation__c NULLS FIRST, Sequence__c, Name
        ];
    }

    public static List<Commission_Rate__c> ratesOf(Id configId) {
        return [
            SELECT Id, Name, Config__c, Designation__c, Designation_Label__c, Rate_Type__c, Current_Rate__c, Exceed_Rate__c,
                   Flat_Amount__c, Target__c, Target_Basis__c, Target_Period__c, Exceed_Mode__c, Split__c, Release_Mode__c,
                   Contract_Reference__c, Claim_Gate__c, Claim_Gate_Label__c, Claim_Mode__c, Aggregate_Of__c, Target_Rule__c, Active__c
            FROM Commission_Rate__c
            WHERE Config__c = :configId
            ORDER BY Name
        ];
    }

    private static void insertRows(Id configId, CommissionDto.Config config) {
        List<Commission_Stage__c> stages = CommissionConfigValidator.stagesOf(config);
        for (Commission_Stage__c row : stages) {
            row.Config__c = configId;
        }
        insert stages;
        List<Commission_Rate__c> rates = CommissionConfigValidator.ratesOf(config);
        for (Commission_Rate__c row : rates) {
            row.Config__c = configId;
        }
        insert rates;
    }

    // ------------------------------------------------------------ users

    public static User finance() {
        return seat(SEAT_FINANCE);
    }

    public static User secondFinance() {
        return seat(SEAT_SECOND_FINANCE);
    }

    public static User approver() {
        return seat(SEAT_APPROVER);
    }

    public static User headOfSales() {
        return seat(SEAT_HEAD_OF_SALES);
    }

    // Reports to headOfSales; holds the role of designation Senior_Manager_Advisor
    public static User seniorManager() {
        return seat(SEAT_SENIOR_MANAGER);
    }

    // Reports to seniorManager; holds the role of designation Sales_Advisor
    public static User advisor() {
        return seat(SEAT_ADVISOR);
    }

    // No capability
    public static User outsider() {
        return seat(SEAT_OUTSIDER);
    }

    private static User seat(String name) {
        if (people == null) {
            Map<String, User> built = new Map<String, User>();
            // Users and roles are setup objects: they are written in their own context, apart from the test's records
            System.runAs(new User(Id = UserInfo.getUserId())) {
                buildPeople(built);
            }
            people = built;
            CommissionAccess.reset();
        }
        return people.get(name);
    }

    // The seven users are created with the profile Standard User. When the org has too few free licences for that
    // (a test insert counts against the licences), existing active users take the seats for the length of the test:
    // their role, manager and profile are changed in the test transaction only, which is rolled back at its end.
    private static void buildPeople(Map<String, User> built) {
        Map<String, Id> roleIds = roles();
        Profile standard = [SELECT Id, UserLicenseId FROM Profile WHERE Name = :PROFILE_NAME LIMIT 1];
        UserLicense licence = [SELECT Id, TotalLicenses, UsedLicenses FROM UserLicense WHERE Id = :standard.UserLicenseId];

        List<Id> userIds = null;
        if (licence.TotalLicenses - licence.UsedLicenses >= SEATS.size()) {
            Savepoint beforeUsers = Database.setSavepoint();
            try {
                List<User> fresh = new List<User>();
                for (String name : SEATS) {
                    fresh.add(newUser(name, standard.Id, roleIds.get(ROLE_OF_SEAT.get(name))));
                }
                insert fresh;
                userIds = new List<Id>();
                for (User person : fresh) {
                    userIds.add(person.Id);
                }
            } catch (DmlException refused) {
                Database.rollback(beforeUsers);
                userIds = null;
            }
        }
        if (userIds == null) {
            userIds = existingUsers(licence.Id, standard.Id, roleIds);
        }

        // The reporting line: advisor -> senior manager -> head of sales
        update new List<User>{
            new User(Id = userIds[SEATS.indexOf(SEAT_SENIOR_MANAGER)], ManagerId = userIds[SEATS.indexOf(SEAT_HEAD_OF_SALES)]),
            new User(Id = userIds[SEATS.indexOf(SEAT_ADVISOR)], ManagerId = userIds[SEATS.indexOf(SEAT_SENIOR_MANAGER)])
        };

        Map<Id, User> byId = new Map<Id, User>([
            SELECT Id, Name, FirstName, LastName, Email, Username, IsActive, ProfileId, Profile.Name, UserRoleId,
                   UserRole.DeveloperName, ManagerId
            FROM User
            WHERE Id IN :userIds
        ]);
        for (Integer i = 0; i < SEATS.size(); i++) {
            built.put(SEATS[i], byId.get(userIds[i]));
        }
    }

    private static Map<String, Id> roles() {
        Set<String> wanted = new Set<String>(ROLE_OF_SEAT.values());
        Map<String, Id> roleIds = new Map<String, Id>();
        for (UserRole role : [SELECT Id, DeveloperName FROM UserRole WHERE DeveloperName IN :wanted]) {
            roleIds.put(role.DeveloperName, role.Id);
        }
        List<UserRole> fresh = new List<UserRole>();
        for (String name : wanted) {
            if (!roleIds.containsKey(name)) {
                fresh.add(new UserRole(DeveloperName = name, Name = name.replace('_', ' ')));
            }
        }
        if (!fresh.isEmpty()) {
            insert fresh;
            for (UserRole role : fresh) {
                roleIds.put(role.DeveloperName, role.Id);
            }
        }
        return roleIds;
    }

    private static User newUser(String name, Id profileId, Id roleId) {
        String token = String.valueOf(Math.abs(Crypto.getRandomLong()));
        return new User(
            FirstName = 'Commission',
            LastName = 'Test ' + name,
            Alias = name.left(8),
            Email = name.toLowerCase() + '@commission-test.example.com',
            Username = name.toLowerCase() + '.' + token + '@commission-test.example.com',
            CommunityNickname = ('ct' + name + token).left(40),
            ProfileId = profileId,
            UserRoleId = roleId,
            TimeZoneSidKey = UserInfo.getTimeZone().getID(),
            LocaleSidKey = UserInfo.getLocale(),
            LanguageLocaleKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            IsActive = true
        );
    }

    // Seven existing active users of the same licence, in the order of the seats. Preferred: users who are nobody's
    // manager and are not administrators, so that a reporting line and the rights are exactly what the test sets.
    private static List<Id> existingUsers(Id licenceId, Id standardProfileId, Map<String, Id> roleIds) {
        Set<Id> managers = new Set<Id>();
        for (User person : [SELECT ManagerId FROM User WHERE ManagerId != null AND IsActive = true]) {
            managers.add(person.ManagerId);
        }
        List<User> plain = new List<User>();
        List<User> leading = new List<User>();
        List<User> administrators = new List<User>();
        for (User person : [
            SELECT Id, ProfileId, Profile.PermissionsModifyAllData
            FROM User
            WHERE IsActive = true AND UserType = 'Standard' AND Profile.UserLicenseId = :licenceId AND Id != :UserInfo.getUserId()
            ORDER BY CreatedDate DESC
            LIMIT 500
        ]) {
            if (person.Profile.PermissionsModifyAllData == true) {
                administrators.add(person);
            } else if (managers.contains(person.Id)) {
                leading.add(person);
            } else {
                plain.add(person);
            }
        }
        List<User> candidates = new List<User>(plain);
        candidates.addAll(leading);
        candidates.addAll(administrators);
        System.assert(candidates.size() >= SEATS.size(),
            'The Commission tests need ' + SEATS.size() + ' free licences of the profile ' + PROFILE_NAME
            + ', or as many other active users to stand in. Found ' + candidates.size() + '.');

        List<Id> userIds = new List<Id>();
        List<User> withProfile = new List<User>();
        List<User> withoutProfile = new List<User>();
        for (Integer i = 0; i < SEATS.size(); i++) {
            Id userId = candidates[i].Id;
            Id roleId = roleIds.get(ROLE_OF_SEAT.get(SEATS[i]));
            userIds.add(userId);
            withProfile.add(new User(Id = userId, UserRoleId = roleId, ManagerId = null, ProfileId = standardProfileId));
            withoutProfile.add(new User(Id = userId, UserRoleId = roleId, ManagerId = null));
        }
        Savepoint beforeChange = Database.setSavepoint();
        try {
            update withProfile;
        } catch (DmlException refused) {
            // A profile that cannot be changed stays: rights come from the roles, the profile lists of the test setting are blank
            Database.rollback(beforeChange);
            update withoutProfile;
        }
        return userIds;
    }

    // ------------------------------------------------------------ builders

    private static CommissionDto.Stage stage(String key, String stageType, Integer sequence, String triggerKey, Decimal triggerPercent,
                                             Decimal releasePercent, String designationKey) {
        CommissionDto.TriggerOption option = CommissionCatalog.triggerByKey().get(triggerKey);
        CommissionDto.Stage entry = new CommissionDto.Stage();
        entry.key = key;
        entry.stageType = stageType;
        entry.sequence = sequence;
        entry.triggerKey = triggerKey;
        entry.triggerLabel = option == null ? null : option.label;
        entry.parameterType = option == null ? null : option.parameterType;
        entry.triggerPercent = triggerPercent;
        entry.releasePercent = releasePercent;
        entry.designation = designationKey;
        return entry;
    }

    private static CommissionDto.Rate rate(String designationKey, Decimal currentRate, Decimal exceedRate, Decimal target) {
        CommissionDto.Designation catalogEntry = CommissionCatalog.designationByKey().get(designationKey);
        CommissionDto.Rate entry = new CommissionDto.Rate();
        entry.key = 'rate-' + designationKey;
        entry.designation = designationKey;
        entry.paid = true;
        entry.currentRate = currentRate;
        entry.exceedRate = exceedRate;
        entry.target = target;
        if (catalogEntry != null) {
            entry.label = catalogEntry.label;
            entry.rateType = catalogEntry.rateType;
            entry.split = catalogEntry.split;
            entry.targetRule = catalogEntry.targetRule;
            entry.claimLabel = catalogEntry.claimLabel;
            entry.aggregateOf = catalogEntry.aggregateOf;
        }
        if (entry.rateType != 'Flat') {
            entry.targetBasis = 'Units';
            entry.targetPeriod = 'Configuration Period';
            entry.exceedMode = 'Marginal';
        }
        return entry;
    }

    private static Commission_Designation__mdt designation(String developerName, String label, Integer position, String rateType, String split,
                                                           String fixedTrigger, String targetRule, String aggregateOf, String claimGate,
                                                           String claimGateLabel, String claimMode, String userRoles) {
        return (Commission_Designation__mdt) metadataRecord(Commission_Designation__mdt.class, 'Commission_Designation__mdt',
            new Map<String, Object>{
                'DeveloperName' => developerName, 'MasterLabel' => label, 'Order__c' => position, 'Rate_Type__c' => rateType,
                'Split__c' => split, 'Fixed_Trigger__c' => fixedTrigger, 'Target_Rule__c' => targetRule,
                'Aggregate_Of__c' => aggregateOf, 'Claim_Gate__c' => claimGate, 'Claim_Gate_Label__c' => claimGateLabel,
                'Claim_Mode__c' => claimMode, 'User_Roles__c' => userRoles, 'Active__c' => true
            });
    }

    private static Commission_Trigger__mdt payoutEvent(String developerName, String label, String stageTypes, String detector, String sourceField,
                                                       String parameterType, String parameterLabel, Integer position, String orderGroup) {
        return (Commission_Trigger__mdt) metadataRecord(Commission_Trigger__mdt.class, 'Commission_Trigger__mdt',
            new Map<String, Object>{
                'DeveloperName' => developerName, 'MasterLabel' => label, 'Stage_Types__c' => stageTypes, 'Detector__c' => detector,
                'Source_Field__c' => sourceField, 'Parameter_Type__c' => parameterType, 'Parameter_Label__c' => parameterLabel,
                'Order__c' => position, 'Order_Group__c' => orderGroup, 'Active__c' => true
            });
    }

    // A custom metadata record in memory. Built from JSON because DeveloperName and MasterLabel cannot be assigned.
    public static SObject metadataRecord(System.Type recordType, String typeName, Map<String, Object> values) {
        Map<String, Object> content = new Map<String, Object>();
        content.put('attributes', new Map<String, Object>{ 'type' => typeName });
        for (String field : values.keySet()) {
            if (values.get(field) != null) {
                content.put(field, values.get(field));
            }
        }
        return (SObject) JSON.deserialize(JSON.serialize(content), recordType);
    }
}