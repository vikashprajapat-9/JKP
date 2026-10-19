// The My Team page of the partner portal.
// A partner is the account of the logged-in portal user's contact. Leads and opportunities belong to a partner through
// their Channel Partner, and the partner's executives are the channel partner accounts whose Channel Head is the
// partner's account. The page shows the partner's figures (their own and their executives' together) and a card per
// executive with that executive's own figures, and its Add Executive form creates such an executive. Only a channel
// head whose Partner Type is Exclusive adds executives: not during their temporary access.
// Partners cannot see their executives' records, so this runs without sharing and in system mode. Every query is
// limited to the logged-in partner's account and the accounts that report to it.
public without sharing class partnerWebPortalMyTeamController {
    // Messages this class shows or sends
    @TestVisible private static final String PARTNER_PORTAL_NO_ACCESS = 'Your Partner Portal access is not active. Please contact the JKP CP team.';
    @TestVisible private static final String PARTNER_TEAM_APPROVAL_COMMENT = 'Executive added by the channel head on the Partner Portal (My Team). Submitted automatically.';
    @TestVisible private static final String PARTNER_TEAM_APPROVAL_NOT_SENT = 'The executive could not be sent for approval right now. Please try again in a few minutes.';
    @TestVisible private static final String PARTNER_TEAM_DOCUMENTS_NOT_READY = 'The executive\'s document folder could not be created right now. Please try again in a few minutes.';
    @TestVisible private static final String PARTNER_TEAM_EXCLUSIVE_ONLY = 'You can add executives once your partnership has exclusive access.';


    private static final String SETTINGS_RECORD = 'Default';
    private static final String LOAD_ERROR = 'Your team could not be loaded right now. Please try again.';
    private static final String NOT_A_PARTNER = 'Only channel partners can add executives.';
    private static final String NOT_A_CHANNEL_HEAD = 'Only channel heads can add executives.';
    private static final String NOT_SET_UP = 'Executives cannot be added right now. Please contact the JKP CP team.';
    private static final Pattern EMAIL_FORMAT = Pattern.compile('^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$');
    private static final Pattern PHONE_FORMAT = Pattern.compile('^\\+?[0-9 ().-]+$');
    private static final Integer MIN_PHONE_DIGITS = 9;
    private static final Integer MAX_PHONE_DIGITS = 15;
    private static final List<String> AVATAR_COLORS = new List<String>{ 'avatar-blue', 'avatar-yellow', 'avatar-green', 'avatar-purple' };

    // The Partner Portal Setting that says which opportunity stages are bookings; tests set their own
    @TestVisible
    private static Partner_Portal_Setting__mdt setting = Partner_Portal_Setting__mdt.getInstance(SETTINGS_RECORD);

    public class TeamStats {
        @AuraEnabled public Integer totalLeads = 0;
        @AuraEnabled public Integer totalBookings = 0;
        @AuraEnabled public Integer totalExecutives = 0;
    }

    public class TeamMember {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String fullName;
        @AuraEnabled public String initials;
        @AuraEnabled public Integer leads = 0;
        @AuraEnabled public Integer bookings = 0;
        @AuraEnabled public String avatarColorClass;
    }

    public class MyTeamResponse {
        @AuraEnabled public String partnerName;
        @AuraEnabled public String partnerInitials;
        @AuraEnabled public TeamStats stats = new TeamStats();
        @AuraEnabled public List<TeamMember> members = new List<TeamMember>();
        // Whether the page offers Add Executive: only to a channel head whose partnership is Exclusive
        @AuraEnabled public Boolean canAddExecutive = false;
    }

    @AuraEnabled(cacheable=true)
    public static MyTeamResponse getMyTeam() {
        try {
            User me = [SELECT Name FROM User WHERE Id = :UserInfo.getUserId() WITH SYSTEM_MODE];
            PartnerPortalAccess access = PartnerPortalAccess.current();
            MyTeamResponse team = teamOf(access);
            team.partnerName = me.Name;
            team.partnerInitials = initialsOf(me.Name);
            team.canAddExecutive = canAddExecutives(access);
            return team;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'My Team could not be loaded: ' + e.getMessage() + '\n' + e.getStackTraceString());
            throw userError(LOAD_ERROR);
        }
    }

    // The Add Executive form. The executive becomes a channel partner account whose Channel Head is the logged-in
    // partner's account, owned by that account's owner, with a contact and a Project Access for each chosen active
    // project. No login is made: like a registration, the account waits for JKP's approval (the Partner Registration
    // Setting's Registration Status) and is sent to the same approval process, on behalf of its owner; approving it
    // releases the portal user, rejecting it emails the executive and frees the email. Only a channel head whose
    // partnership is Exclusive may add executives (canAddExecutives). Returns the new account's Id.
    @AuraEnabled
    public static Id addExecutive(String fullName, String reportingTo, String email, String phone, List<Id> projectIds) {
        String name = fullName == null ? '' : fullName.normalizeSpace();
        String reportsTo = reportingTo == null ? '' : reportingTo.normalizeSpace();
        String mail = email == null ? '' : email.trim();
        String phoneNumber = phone == null ? '' : phone.trim();
        if (String.isBlank(name) || name.length() > Schema.SObjectType.Account.fields.Name.getLength()) {
            throw userError('Enter the executive\'s full name.');
        }
        if (String.isBlank(reportsTo) || reportsTo.length() > Schema.SObjectType.Account.fields.Field_Reporting_To__c.getLength()) {
            throw userError('Enter who the executive reports to in the field.');
        }
        if (!EMAIL_FORMAT.matcher(mail).matches() || mail.length() > Schema.SObjectType.Contact.fields.Email.getLength()) {
            throw userError('Enter a valid email address.');
        }
        if (!isPhone(phoneNumber)) {
            throw userError('Enter a valid phone number.');
        }
        Set<Id> chosenProjects = projectIds == null ? new Set<Id>() : new Set<Id>(projectIds);
        chosenProjects.remove(null);
        if (chosenProjects.isEmpty()) {
            throw userError('Select at least one project.');
        }

        User me = [SELECT ContactId, Contact.AccountId FROM User WHERE Id = :UserInfo.getUserId() WITH SYSTEM_MODE];
        Id partnerAccountId = me.ContactId == null ? null : me.Contact.AccountId;
        if (partnerAccountId == null) {
            throw userError(NOT_A_PARTNER);
        }
        PartnerPortalAccess access = PartnerPortalAccess.current();
        // A partner whose portal access ended (Access Denied, Terminated) cannot add executives
        if (access.accountId == null) {
            throw userError(PARTNER_PORTAL_NO_ACCESS);
        }
        // Executives are onboarded by their channel head and cannot onboard others
        if (access.isExecutive) {
            throw userError(NOT_A_CHANNEL_HEAD);
        }
        // A channel head adds executives once their partnership is Exclusive, not during their temporary access
        if (!canAddExecutives(access)) {
            throw userError(PARTNER_TEAM_EXCLUSIVE_ONLY);
        }
        // The executive is owned like the partner's own account: by an active internal user, as partner accounts must be
        Account head = [SELECT OwnerId, Owner.IsActive, Owner.UserType FROM Account WHERE Id = :partnerAccountId WITH SYSTEM_MODE];
        Id channelPartnerType = partnerPortalRegistrationController.partnerRecordTypeId();
        if (channelPartnerType == null || !head.Owner.IsActive || head.Owner.UserType != 'Standard') {
            throw userError(NOT_SET_UP);
        }
        List<Project__c> projects = [SELECT Id FROM Project__c WHERE Id IN :chosenProjects AND Active__c = true WITH SYSTEM_MODE];
        if (projects.size() != chosenProjects.size()) {
            throw userError('A selected project is no longer available. Please choose the projects again.');
        }
        // A rejected executive does not keep its email (like a rejected registration): the head may add the person again
        String rejected = rejectedStatus();
        Integer sameEmail = [
            SELECT COUNT() FROM Account
            WHERE RecordTypeId = :channelPartnerType AND Email__c = :mail AND Onboarding_Status__c != :rejected WITH SYSTEM_MODE
        ] + [
            SELECT COUNT() FROM Contact
            WHERE Account.RecordTypeId = :channelPartnerType AND Email = :mail AND Account.Onboarding_Status__c != :rejected WITH SYSTEM_MODE
        ];
        if (sameEmail > 0) {
            throw userError('A partner or executive with this email already exists.');
        }

        // SharePoint comes first, as in a registration: no callout may follow DML, and once the account is sent for approval
        // it is locked, so the folder job of the account trigger (which runs as this partner) could no longer save the
        // folder on it. With its folder already set, the trigger queues no job. If the folder cannot be made nothing is
        // saved and the partner can try again. A folder made for an add that then fails stays in SharePoint, empty: a
        // callout cannot be undone, and folders are never deleted from here.
        String folderId;
        String recordTypeName = Schema.SObjectType.Account.getRecordTypeInfosById().get(channelPartnerType).getName();
        if (!DocumentCreationHandler.categoriesForRecordType(recordTypeName).isEmpty()) {
            try {
                folderId = SharePointDocumentManagerController.createFolder(null, name);
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Add Executive: the SharePoint folder could not be made: ' + e.getMessage());
            }
            if (String.isBlank(folderId)) {
                throw userError(PARTNER_TEAM_DOCUMENTS_NOT_READY);
            }
        }

        Savepoint beforeSaving = Database.setSavepoint();
        try {
            Account executive = new Account(Name = name, RecordTypeId = channelPartnerType, Channel_Head__c = partnerAccountId,
                Field_Reporting_To__c = reportsTo, Email__c = mail, Phone = phoneNumber, OwnerId = head.OwnerId,
                Onboarding_Status__c = partnerPortalRegistrationController.registrationStatus(), Document_Id__c = folderId);
            Database.insert(executive, AccessLevel.SYSTEM_MODE);
            List<String> names = contactNames(name);
            Database.insert(new Contact(FirstName = names[0], LastName = names[1], Email = mail, Phone = phoneNumber,
                AccountId = executive.Id, OwnerId = head.OwnerId), AccessLevel.SYSTEM_MODE);
            List<Project_Access__c> projectAccess = new List<Project_Access__c>();
            for (Project__c project : projects) {
                projectAccess.add(new Project_Access__c(Account__c = executive.Id, Project__c = project.Id, OwnerId = head.OwnerId));
            }
            Database.insert(projectAccess, AccessLevel.SYSTEM_MODE);
            if (folderId != null) {
                // A Document per category, each with its sub-folder (made by the folder job; Documents are not locked)
                new DocumentCreationHandler().CreateDocuments(new List<Account>{ executive });
            }
            // The CP Manager's approval, asked for like a registration's. If it cannot be asked for, nothing is saved
            // and the partner can try again.
            if (!partnerPortalRegistrationController.sendForApproval(executive.Id, head.OwnerId, PARTNER_TEAM_APPROVAL_COMMENT)) {
                Database.rollback(beforeSaving);
                throw userError(PARTNER_TEAM_APPROVAL_NOT_SENT);
            }
            return executive.Id;
        } catch (DmlException e) {
            // Validation rules speak to the user; nothing of the executive stays saved
            System.debug(LoggingLevel.ERROR, 'Add Executive failed: ' + e.getMessage());
            Database.rollback(beforeSaving);
            throw userError(e.getDmlMessage(0));
        }
    }

    // The Onboarding Status of rejected executives and registrations (Partner Registration Setting). When none is set
    // up, a value no account has: comparing with null would leave out every account without a status.
    private static String rejectedStatus() {
        String rejected = partnerPortalRegistrationController.rejectedStatus();
        return rejected == null ? NO_SUCH_STATUS : rejected;
    }

    private static final String NO_SUCH_STATUS = '(no rejected status)';

    // Whether the partner may add executives: a channel head with portal access whose Partner Type is Exclusive (as it
    // becomes once its exclusive agent contract is signed, PartnerContractService). Not during the temporary access,
    // nor without a Partner Type.
    private static Boolean canAddExecutives(PartnerPortalAccess access) {
        if (access.accountId == null || access.isExecutive) {
            return false;
        }
        Account partner = [SELECT Partner_Type__c FROM Account WHERE Id = :access.accountId WITH SYSTEM_MODE];
        return partner.Partner_Type__c == PartnerTemporaryAccess.EXCLUSIVE;
    }

    // The partner's figures and executives (PartnerPortalAccess): a channel head's team, an executive's own records and
    // no executives. A user without a partner account (an internal user) has none.
    private static MyTeamResponse teamOf(PartnerPortalAccess access) {
        MyTeamResponse team = new MyTeamResponse();
        Id partnerAccountId = access.accountId;
        if (partnerAccountId == null) {
            return team;
        }
        Set<String> bookingStages = bookingStages();
        Map<String, Object> binds = new Map<String, Object>{ 'bookingStages' => bookingStages };
        team.stats.totalLeads = Database.countQueryWithBinds('SELECT COUNT() FROM Lead WHERE ' + access.leads(binds), binds, AccessLevel.SYSTEM_MODE);
        team.stats.totalBookings = Database.countQueryWithBinds(
            'SELECT COUNT() FROM Opportunity WHERE ' + access.opportunities(binds) + ' AND StageName IN :bookingStages', binds, AccessLevel.SYSTEM_MODE);

        // Executives have the channel partner record type of the Partner Registration Setting; without it there are none.
        // An executive has no executives of their own.
        Id channelPartnerType = partnerPortalRegistrationController.partnerRecordTypeId();
        if (channelPartnerType == null || access.isExecutive) {
            return team;
        }
        // A rejected executive is no longer on the team
        String rejected = rejectedStatus();
        List<Account> executives = [
            SELECT Id, Name FROM Account
            WHERE RecordTypeId = :channelPartnerType AND Channel_Head__c = :partnerAccountId AND Id != :partnerAccountId
                AND Onboarding_Status__c != :rejected
            WITH SYSTEM_MODE
            ORDER BY Name
        ];
        team.stats.totalExecutives = executives.size();
        if (executives.isEmpty()) {
            return team;
        }

        Set<Id> executiveIds = new Map<Id, Account>(executives).keySet();
        Map<Id, Integer> leadsByExecutive = countsByChannelPartner([
            SELECT Channel_Partner__c channelPartner, COUNT(Id) recordCount FROM Lead
            WHERE Channel_Partner__c IN :executiveIds AND CP_Approval_Status__c != 'Rejected'
            WITH SYSTEM_MODE
            GROUP BY Channel_Partner__c
        ]);
        Map<Id, Integer> bookingsByExecutive = countsByChannelPartner([
            SELECT Channel_Partner__c channelPartner, COUNT(Id) recordCount FROM Opportunity
            WHERE Channel_Partner__c IN :executiveIds AND StageName IN :bookingStages
            WITH SYSTEM_MODE
            GROUP BY Channel_Partner__c
        ]);
        for (Account executive : executives) {
            TeamMember member = new TeamMember();
            member.accountId = executive.Id;
            member.fullName = executive.Name;
            member.initials = initialsOf(executive.Name);
            member.leads = leadsByExecutive.containsKey(executive.Id) ? leadsByExecutive.get(executive.Id) : 0;
            member.bookings = bookingsByExecutive.containsKey(executive.Id) ? bookingsByExecutive.get(executive.Id) : 0;
            member.avatarColorClass = AVATAR_COLORS[Math.mod(team.members.size(), AVATAR_COLORS.size())];
            team.members.add(member);
        }
        return team;
    }

    private static Map<Id, Integer> countsByChannelPartner(List<AggregateResult> rows) {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        for (AggregateResult row : rows) {
            counts.put((Id) row.get('channelPartner'), (Integer) row.get('recordCount'));
        }
        return counts;
    }

    // The opportunity stages that count as bookings: the active stages that come after the setting's Bookings After
    // Stage in the Stage picklist order, except its Stages Not Counted As Bookings and closed lost stages. Stages are
    // matched by API name or label in any capitals. Empty when the setting or its stage is missing. The Leads page's
    // Booked filter uses the same stages.
    public static Set<String> bookingStages() {
        Set<String> stages = new Set<String>();
        String afterStage = setting == null ? null : setting.Bookings_After_Stage__c;
        if (String.isBlank(afterStage)) {
            return stages;
        }
        afterStage = afterStage.trim();
        Set<String> notBookings = new Set<String>();
        if (String.isNotBlank(setting.Stages_Not_Counted_As_Bookings__c)) {
            for (String stageName : setting.Stages_Not_Counted_As_Bookings__c.split('[,;]')) {
                notBookings.add(stageName.trim().toLowerCase());
            }
        }
        Boolean pastAfterStage = false;
        for (OpportunityStage stage : [
            SELECT ApiName, MasterLabel, IsClosed, IsWon FROM OpportunityStage
            WHERE IsActive = true
            WITH SYSTEM_MODE
            ORDER BY SortOrder
        ]) {
            Boolean lost = stage.IsClosed && !stage.IsWon;
            Boolean excluded = notBookings.contains(stage.ApiName.toLowerCase()) || notBookings.contains(stage.MasterLabel.toLowerCase());
            if (pastAfterStage && !lost && !excluded) {
                stages.add(stage.ApiName);
            }
            if (stage.ApiName.equalsIgnoreCase(afterStage) || stage.MasterLabel.equalsIgnoreCase(afterStage)) {
                pastAfterStage = true;
            }
        }
        return stages;
    }

    // The first letters of the first two words, as the portal's top bar shows the logged-in user
    private static String initialsOf(String name) {
        String initials = '';
        if (String.isNotBlank(name)) {
            for (String word : name.trim().split('\\s+')) {
                if (initials.length() == 2) {
                    break;
                }
                initials += word.left(1);
            }
        }
        return initials.toUpperCase();
    }

    // A contact's first and last name from a full name: the last word is the last name, the words before it the first name
    private static List<String> contactNames(String name) {
        Integer lastSpace = name.lastIndexOf(' ');
        String firstName = lastSpace < 0 ? null : name.left(lastSpace).left(Schema.SObjectType.Contact.fields.FirstName.getLength());
        String lastName = (lastSpace < 0 ? name : name.substring(lastSpace + 1)).left(Schema.SObjectType.Contact.fields.LastName.getLength());
        return new List<String>{ firstName, lastName };
    }

    // 9 to 15 digits, optionally after a +, with spaces, brackets, dots or dashes
    private static Boolean isPhone(String value) {
        if (String.isBlank(value) || !PHONE_FORMAT.matcher(value).matches() || value.length() > Schema.SObjectType.Contact.fields.Phone.getLength()) {
            return false;
        }
        Integer digits = value.replaceAll('[^0-9]', '').length();
        return digits >= MIN_PHONE_DIGITS && digits <= MAX_PHONE_DIGITS;
    }

    private static AuraHandledException userError(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}