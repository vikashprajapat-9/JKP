public class LeadLogicController {

	public static void calculateLeadScore(List<Lead> leads) {
        if(leads.isEmpty()){
            return;
        }
        List<Lead_Score_Field__mdt> fieldConfigs = [
            SELECT Field_API_Name__c
            FROM Lead_Score_Field__mdt
            WHERE Active__c = true
            WITH SYSTEM_MODE
            ORDER BY Display_Order__c ASC NULLS LAST
        ];
        Set<String> values = new Set<String>();
        for(Lead l : leads){
            for (Lead_Score_Field__mdt fieldConfig : fieldConfigs) {
                Object fieldValue = l.get(fieldConfig.Field_API_Name__c);
                if (fieldValue != null && String.isNotBlank(String.valueOf(fieldValue))) {
                    values.add(String.valueOf(fieldValue));
                }
            }
        }
        Map<String, Decimal> scoreMap = new Map<String, Decimal>();
		List<Lead_Priority_Configs__c> priorityConfigs = [
                                                            SELECT Min_Score__c, Max_Score__c, Priority__c 
                                                            FROM Lead_Priority_Configs__c 
                                                            WHERE Active__c = true 
                                                            WITH SYSTEM_MODE
                                                            ORDER BY Min_Score__c ASC
                                                        ];
        for(Lead_Score_Config__c cfg : [
                                        SELECT Field_API_Name__c,Picklist_Value__c,Score__c,Active__c 
                                        FROM Lead_Score_Config__c 
                                        WHERE Active__c = true 
                                        AND Picklist_Value__c IN :values
                                        WITH SYSTEM_MODE
                                        ]){
            if (String.isBlank(cfg.Field_API_Name__c) || String.isBlank(cfg.Picklist_Value__c)) {
                continue;
            }
            String key = cfg.Field_API_Name__c + '-' + cfg.Picklist_Value__c;
            scoreMap.put(key,cfg.Score__c);
        }
        for(Lead l : leads){			 
			if (l.LeadSource == 'Digital' && (l.Lead_Sub_Source__c == 'Website Forms' || l.Lead_Sub_Source__c == 'LinkedIn Ads')) {
				l.Lead_Classification__c = 'Hot';
			}
			
            if(l.LeadSource == 'Digital' && (l.Lead_Sub_Source__c == 'Meta Form Ads' || l.Lead_Sub_Source__c == 'Meta Lead Ads')){
                Decimal totalScore = 0;
                for (Lead_Score_Field__mdt fieldConfig : fieldConfigs) {
                    Object fieldValue = l.get(fieldConfig.Field_API_Name__c);
                    totalScore += getScore(
                        scoreMap,
                        fieldConfig.Field_API_Name__c,
                        fieldValue == null ? null : String.valueOf(fieldValue)
                    );
                }
                l.Lead_Score__c = totalScore;
                for (Lead_Priority_Configs__c cfg : priorityConfigs) {
                    if (totalScore >= cfg.Min_Score__c && totalScore <= cfg.Max_Score__c) {
                        l.Lead_Classification__c = cfg.Priority__c;
                        break;
                    }
                }
            }
        }
    }

    private static Decimal getScore( Map<String,Decimal> scoreMap, String fieldApi, String value ){
        if(String.isBlank(value)){
            return 0;
        }
        String key = fieldApi + '-' + value;
        return scoreMap.containsKey(key) ? scoreMap.get(key): 0;
    }


    public static void normalizePhone(List<Lead> leads) {
        for (Lead l : leads) {

            if (String.isBlank(l.Phone)) {
                l.Normalised_Phone__c = null;
                continue;
            }
            l.Normalised_Phone__c = normalisedPhoneOf(l.Phone);
        }
    }

    // Sri Lanka's country code: a local mobile is 0 + 9 digits, or 94 / 0094 + the same 9 digits
    private static final String COUNTRY_CODE = '94';
    private static final Integer NATIONAL_DIGITS = 9;

    // The phone number the duplicate checks compare, so that the ways one number is written match: its digits only,
    // a Sri Lankan number without its 0 or country code (077 123 4567, +94 77 123 4567, 0094 77 123 4567 and
    // +94 077 123 4567 are 771234567), any other number its last 10 digits
    public static String normalisedPhoneOf(String phone) {
        if (String.isBlank(phone)) {
            return null;
        }
        String digits = phone.replaceAll('[^0-9]', '');
        // 0094 or 94 and the national number, sometimes still typed with its 0
        for (String prefix : new List<String>{ '00' + COUNTRY_CODE, COUNTRY_CODE }) {
            Integer national = digits.length() - prefix.length();
            if (digits.startsWith(prefix)
                    && (national == NATIONAL_DIGITS || (national == NATIONAL_DIGITS + 1 && digits.substring(prefix.length()).startsWith('0')))) {
                digits = digits.substring(prefix.length());
                break;
            }
        }
        if (digits.length() == NATIONAL_DIGITS + 1 && digits.startsWith('0')) {
            return digits.substring(1);
        }
        return digits.length() > 10 ? digits.substring(digits.length() - 10) : digits;
    }

    // A lead's Mobile Number: digits with spaces, brackets or dashes and an optional leading + (what the Lead phone
    // validation rule accepts), holding 9 to 15 digits without a leading 0
    private static final Pattern PHONE_FORMAT = Pattern.compile('^\\+?[0-9 ()-]+$');
    private static final Integer MIN_PHONE_DIGITS = 9;
    private static final Integer MAX_PHONE_DIGITS = 15;

    public static Boolean isPhoneNumber(String value) {
        if (String.isBlank(value) || !PHONE_FORMAT.matcher(value.trim()).matches()) {
            return false;
        }
        Integer digits = value.replaceAll('[^0-9]', '').replaceFirst('^0+', '').length();
        return digits >= MIN_PHONE_DIGITS && digits <= MAX_PHONE_DIGITS;
    }

    public static void validateLeads(List<Lead> leads) {
        for (Lead l : leads) {
            // Last Name
            if (String.isBlank(l.LastName) ||
                l.LastName.length() < 2 ||
                l.LastName.replaceAll('[^0-9]', '') == l.LastName) {
                l.addError('Please enter a valid Lead Name.');
            }
            // Phone
            if (String.isBlank(l.Phone)) {
                l.addError('Please enter a valid phone number.');
            }
            //  Budget Range
            if (String.isBlank(l.Budget_Aligned__c)) {
                l.addError('Please select a valid Budget Range.');
            }
            //  Lead Source
            if (String.isBlank(l.LeadSource)) {
                l.addError('Please select a valid Lead Source.');
            }

            // Project
            if (l.Project__c == null) {
                l.addError('Please select the Interested Project.');
            }

            // priority
            if (
                l.LeadSource == 'Manual' &&
                l.Lead_Classification__c != 'Hot' &&
                l.Lead_Classification__c != 'Warm'
            ) {
                l.addError('Manually created leads must be classified as Hot or Warm.');
            }
        }
    }
    public static void createLeadHistory( List<Lead> newLeads,Map<Id, Lead> oldMap, Boolean isInsert) {
        if (newLeads == null || newLeads.isEmpty()) {
            return;
        }
        Set<Id> leadIds = new Set<Id>();
        for (Lead lead : newLeads) {
            if (lead.Id != null) {
                leadIds.add(lead.Id);
            }
        }
        Map<Id, Lead_Assignment_History__c> latestHistoryByLead = new Map<Id, Lead_Assignment_History__c>();
        for (Lead_Assignment_History__c history : [ SELECT Id, Lead__c, Lead_Assigned_To__c, OwnerId, CreatedDate
                                                    FROM Lead_Assignment_History__c WHERE Lead__c IN :leadIds WITH SYSTEM_MODE ORDER BY CreatedDate DESC
        ]) {
            if (!latestHistoryByLead.containsKey(history.Lead__c)) {
                latestHistoryByLead.put(history.Lead__c, history);
            }
        }
        List<Lead_Assignment_History__c> historyList = new List<Lead_Assignment_History__c>();
        for (Lead lead : newLeads) {
            if (lead.OwnerId == null) {
                continue;
            }

            Boolean isUserOwner = String.valueOf(lead.OwnerId).startsWith('005');
            if (!isUserOwner) {
                continue;
            }
            Boolean ownerChanged = false;
            if (isInsert) {
                ownerChanged = true;
            }
            else {
                Lead oldLead = oldMap.get(lead.Id);
                if ( oldLead != null &&  oldLead.OwnerId != lead.OwnerId
                ) {
                    ownerChanged = true;
                }
            }
            if (!ownerChanged) {
                continue;
            }
            Lead_Assignment_History__c latestHistory =  latestHistoryByLead.get(lead.Id);
            if ( latestHistory != null && latestHistory.Lead_Assigned_To__c == lead.OwnerId) {
                System.debug( 'Assignment history already exists for Lead ' + lead.Id +' and User ' +  lead.OwnerId);
                continue;
            }
            Lead_Assignment_History__c history = new Lead_Assignment_History__c();
            history.Lead__c = lead.Id;
            history.Lead_Assigned_To__c = lead.OwnerId;
            history.OwnerId = lead.OwnerId;

            history.SLA1__c = false;
            history.SLA2__c = false;

            historyList.add(history);
        }

        if (!historyList.isEmpty()) {
            System.debug( 'Creating Lead Assignment History records: ' + historyList.size());
            // Org-wide: the owner may be a JKP user the saving partner cannot see (the hand-over after a portal visit)
            new OrgWide().insertRecords(historyList);
        }
    }
    

    private static Boolean isSameSource(Lead existingLead, Lead newLead){
        return existingLead.LeadSource == newLead.LeadSource;
    }

    private static Boolean isSameSubSource(Lead existingLead, Lead newLead){
        return existingLead.Lead_Sub_Source__c == newLead.Lead_Sub_Source__c;
    }
    // The duplicate check of the leads that are not channel partner leads (a CP lead follows the CP rules,
    // prepareChannelPartnerLeads). For a customer (normalised phone + project) already in the org:
    //  - Direct Sales or another non-CP source has it (CASE 1): the new lead is refused and becomes a Re-Enquiry on the
    //    oldest such lead (on its opportunity when it was converted);
    //  - only channel partners have it (CASE 4): refused during the channel partner lock-in (the Partner Portal
    //    Setting's CP Lock-in Days from the latest CP submission), and a new lead after that.
    // A CP lead is one with the channel partner Lead Source or a Channel Partner; CP leads the managers rejected are
    // left out (no lead was created for that CP).
    public static void checkDuplicateLead(List<Lead> leads) {
        Set<String> phones = new Set<String>();
        Set<Id> projectIds = new Set<Id>();
        for (Lead l : leads) {
            if (String.isNotBlank(l.Normalised_Phone__c)) {
                phones.add(l.Normalised_Phone__c);
            }
            if (l.Project__c != null) {
                projectIds.add(l.Project__c);
            }
        }
        if (phones.isEmpty() || projectIds.isEmpty()) {
            return;
        }
        // Every existing lead of each customer, oldest first
        Map<String, List<Lead>> existingByKey = new Map<String, List<Lead>>();
        for (Lead l : new OrgWide().leadsWithPhoneInProjects(phones, projectIds)) {
            String key = l.Normalised_Phone__c + '#' + String.valueOf(l.Project__c);
            if (!existingByKey.containsKey(key)) {
                existingByKey.put(key, new List<Lead>());
            }
            existingByKey.get(key).add(l);
        }
        Decimal lockInDays = portalSetting == null ? null : portalSetting.CP_Lock_In_Days__c;
        List<Lead_Duplicate_Event__e> events = new List<Lead_Duplicate_Event__e>();
        for (Lead newLead : leads) {
            String key = newLead.Normalised_Phone__c + '#' + String.valueOf(newLead.Project__c);
            if (!existingByKey.containsKey(key) || isChannelPartnerLead(newLead)) {
                continue;
            }
            Lead existingLead;
            Lead latestChannelPartnerLead;
            for (Lead existing : existingByKey.get(key)) {
                if (!ownedByChannelPartner(existing)) {
                    if (existingLead == null) {
                        existingLead = existing;
                    }
                } else if (latestChannelPartnerLead == null || existing.CreatedDate > latestChannelPartnerLead.CreatedDate) {
                    latestChannelPartnerLead = existing;
                }
            }
            //----------------------------------------------------
            // CASE 1
            // Existing = Digital/Manual (or another non-CP source)
            // Incoming = Digital/Manual
            //----------------------------------------------------
            if (existingLead != null) {
                Lead_Duplicate_Event__e eventRec = new Lead_Duplicate_Event__e();
                if(existingLead.IsConverted){
                    eventRec.Existing_Opportunity_Id__c = existingLead.ConvertedOpportunityId;
                }
                eventRec.Existing_Lead_Id__c = existingLead.Id;
                eventRec.New_Lead_Source__c = newLead.LeadSource;
                eventRec.New_Lead_Sub_Source__c = newLead.Lead_Sub_Source__c;
                events.add(eventRec);
                newLead.addError('Lead already exists. Re-Enquiry has been created.');
            }
            //----------------------------------------------------
            // CASE 4
            // Existing CP only
            // Incoming Digital/Manual: refused during the CP lock-in
            //----------------------------------------------------
            else if (latestChannelPartnerLead != null && lockInDays != null && lockInDays > 0) {
                Date expiry = latestChannelPartnerLead.CreatedDate.date().addDays(lockInDays.intValue());
                if (Date.today() <= expiry) {
                    newLead.addError(String.format(Label.CP_Lead_Lock_In_Active, new List<Object>{ expiry.format() }));
                }
            }
        }
        if(!events.isEmpty()){
            LeadSystemOperations.publish(events);
        }
    }

    public static void sendEmailToLeadOwnerOnAssignment(List<Lead> leadsToSendmail) {
        if (leadsToSendmail == null || leadsToSendmail.isEmpty()) {
            return;
        }
        Set<Id> leadIdSet = new Set<Id>();
        for (Lead lead : leadsToSendmail) {
            if (lead.Id != null) {
                leadIdSet.add(lead.Id);
            }
        }
        if (leadIdSet.isEmpty()) {
            return;
        }
        List<Lead> leads = [
            SELECT
                Id, Name, FirstName, LastName, Status, Lead_Classification__c, OwnerId, Lead_Assigned_Date_Time__c
            FROM Lead
            WHERE Id IN :leadIdSet
            WITH SYSTEM_MODE
        ];
        if (leads.isEmpty()) {
            return;
        }
        List<Task> tasksToInsert = new List<Task>();
        List<Messaging.SingleEmailMessage> emailsToSend = new List<Messaging.SingleEmailMessage>();
        Set<Id> userIdSet = new Set<Id>();
        for (Lead lead : leads) {
            if (lead.OwnerId != null) {
                userIdSet.add(lead.OwnerId);
            }
        }
        if (userIdSet.isEmpty()) {
            return;
        }
        List<EmailTemplate> template = [
            SELECT Subject, HtmlValue
            FROM EmailTemplate
            WHERE DeveloperName = 'Lead_Assigned_to_Owner'
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (template.isEmpty()) {
            return;
        }
        List<OrgWideEmailAddress> oweaList = [
            SELECT Id
            FROM OrgWideEmailAddress
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        Map<Id, User> usersMap = new Map<Id, User>([
            SELECT Id, Name, Email
            FROM User
            WHERE Id IN :userIdSet
            WITH SYSTEM_MODE
        ]);
        if (usersMap.isEmpty()) {
            return;
        }
        Map<String, ContentAsset> logoAssetsMap = new Map<String, ContentAsset>();
        for (ContentAsset asset : [
            SELECT
                Id,
                DeveloperName,
                MasterLabel,
                ContentDocumentId,
                IsVisibleByExternalUsers
            FROM ContentAsset
            WHERE DeveloperName IN ('Logo_White', 'Logo_Blue')
            WITH SYSTEM_MODE
        ]) {
            logoAssetsMap.put(asset.DeveloperName, asset);
        }
        String orgId = UserInfo.getOrganizationId();
        String orgDomainUrl = URL.getOrgDomainUrl().toExternalForm();
        String jkpWhiteLogoUrl = '';
        String jkpBlueLogoUrl = '';
        if (logoAssetsMap.containsKey('Logo_White')) {
            ContentAsset whiteLogo = logoAssetsMap.get('Logo_White');
            jkpWhiteLogoUrl = orgDomainUrl + '/file-asset-public/' + whiteLogo.DeveloperName + '?oid=' + orgId;
        }
        if (logoAssetsMap.containsKey('Logo_Blue')) {
            ContentAsset blueLogo = logoAssetsMap.get('Logo_Blue');
            jkpBlueLogoUrl = orgDomainUrl + '/file-asset-public/' + blueLogo.DeveloperName + '?oid=' + orgId;
        }
        for (Lead l : leads) {
            if (l.OwnerId == null || !usersMap.containsKey(l.OwnerId)) {
                continue;
            }
            User owner = usersMap.get(l.OwnerId);
            if (String.isBlank(owner.Email)) {
                continue;
            }
            String body = template[0].HtmlValue;
            body = body.replace('{!Lead.Name}', String.isBlank(l.Name) ? '' : l.Name);
            body = body.replace('{!Lead.Status}', String.isBlank(l.Status) ? '' : l.Status);
            body = body.replace('{!Lead.Lead_Classification__c}', String.isBlank(l.Lead_Classification__c) ? '' : l.Lead_Classification__c);
            body = body.replace('{!Lead.OwnerFullName}', String.isBlank(owner.Name) ? '' : owner.Name);
            String leadUrl = orgDomainUrl + '/' + l.Id;
            body = body.replace('{!Lead.Link}', leadUrl);
            body = body.replace('{{JKP_LOGO_WHITE}}', jkpWhiteLogoUrl);
            body = body.replace('{{JKP_LOGO_BLUE}}', jkpBlueLogoUrl);
            String subject = template[0].Subject;
            subject = subject.replace('{!Lead.Name}', String.isBlank(l.Name) ? '' : l.Name);
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            if(l.Lead_Classification__c == 'Hot') {
                Task tk = new Task();
                tk.Subject = 'Contact the lead within 1 hr';
                tk.Status = 'Not Started';
                tk.Priority = 'Normal';
                tk.OwnerId = l.OwnerId;
                tk.WhoId = l.Id;
                tk.ActivityDate = l.Lead_Assigned_Date_Time__c == null ? Date.today() : l.Lead_Assigned_Date_Time__c.date();
                tk.Description = 'Follow-up generated after Lead Assignment.';
                tasksToInsert.add(tk);
            } else {
                Task tk = new Task();
                tk.Subject = 'Contact the lead within 4 hrs';
                tk.Status = 'Not Started';
                tk.Priority = 'Normal';
                tk.OwnerId = l.OwnerId;
                tk.WhoId = l.Id;
                tk.ActivityDate = l.Lead_Assigned_Date_Time__c == null ? Date.today() : l.Lead_Assigned_Date_Time__c.date();
                tk.Description = 'Follow-up generated after Lead Assignment.';
                tasksToInsert.add(tk);
            }
            mail.setToAddresses(new String[] { owner.Email });
            if (!oweaList.isEmpty()) {
                mail.setOrgWideEmailAddressId(
                    oweaList[0].Id
                );
            }
            mail.setSaveAsActivity(false);
            mail.setHtmlBody(body);
            mail.setSubject(subject);
            emailsToSend.add(mail);
        }
        if(!tasksToInsert.isEmpty()) {
            Database.insert(tasksToInsert, AccessLevel.SYSTEM_MODE);
        }
        if (!emailsToSend.isEmpty()) {
            Messaging.sendEmail(emailsToSend);
        }
    }

    /**
     * Qualify or disqualify a Lead from the Lead Record Page.
     * Can only be called when the Lead is in "Contacted" status.
     *
     * @param leadId  – Id of the Lead to update
     * @param status  – "Qualified" or "Not Qualified"
     * @param reason  – Mandatory reason for the qualification decision
     */
    @AuraEnabled
    public static void qualifyLead(Id leadId, String status, String reason) {
        if (leadId == null) {
            throw new AuraHandledException('Lead ID is required.');
        }
        if (String.isBlank(status) ||
            (status != 'Qualified' && status != 'Not Qualified')) {
            throw new AuraHandledException(
                'Invalid qualification status. Allowed values: "Qualified" or "Not Qualified".'
            );
        }
        if (String.isBlank(reason)) {
            throw new AuraHandledException(
                'Qualification Status Reason is mandatory.'
            );
        }

        Lead lead;
        try {
            lead = [
                SELECT Id, Status
                FROM Lead
                WHERE Id = :leadId
                LIMIT 1
            ];
        } catch (QueryException e) {
            throw new AuraHandledException('Lead record not found.');
        }

        if (lead.Status != 'Contacted') {
            throw new AuraHandledException(
                'Lead must be in "Contacted" status to qualify. Current status: ' + lead.Status
            );
        }

        lead.Status = status;
        lead.Qualification_Status_Reason__c = reason;

        try {
            update lead;
        } catch (DmlException e) {
            throw new AuraHandledException(
                'Failed to update the Lead: ' + e.getMessage()
            );
        }
    }


    // =====================================================================================================
    // CHANNEL PARTNER LEADS
    // The lead process for the leads a channel partner (CP) submits, from any source (the partner portal today).
    // It runs from LeadTrigger, so every way of creating a CP lead gets the same rules, and a refusal reaches the
    // caller as the DML error (the portal shows it):
    //  1. Mandatory fields: Full Name, Mobile Number, Email ID, Interested Project (Name, Phone format, Budget and
    //     Project are also Lead validation rules; if they fail, the lead is not saved and nothing is submitted). The
    //     Mobile Number must hold 9 to 15 digits, as in the other portal forms.
    //  2. Duplicate check on Phone + Project (the normalised phone) against every lead in the org. A channel head and
    //     their executives are one CP (one team):
    //     - not a duplicate: the lead is created and moves to Assigned;
    //     - the same CP team already submitted the customer for the project: refused;
    //     - another CP has it (CP -> CP): created, with a notice that ownership goes to whichever CP completes the
    //       first successful site visit; refused once another CP has completed a site visit with the customer (or
    //       converted it). When a site visit is completed, the other CPs' leads for the customer are closed with the
    //       CP Lead Lost Status, their open visits cancelled and their partners emailed (applyFirstSiteVisitRule);
    //     - Direct Sales or a referral has it (Direct/Referral -> CP): the CP's lead is saved as Pending approval and
    //       sent to the CP Lead Approval process, where the Direct Sales Manager (the existing lead owner's manager)
    //       and the JKP CP Manager (the CP account owner's manager) must both approve; when a manager is missing (a
    //       queue's lead, a user without an active manager) the Partner Portal Setting's backup approver takes their
    //       place. Approved: the lead moves to Assigned. Rejected: it stays as Rejected, hidden from the partner
    //       portal, and the CP agent is emailed.
    // The messages are custom labels (CP_Lead_*); the statuses and backup approvers are Partner Portal Settings.
    // =====================================================================================================

    public static final String CP_CREATED = 'CREATED';
    public static final String CP_CREATED_WITH_NOTICE = 'CREATED_WITH_NOTICE';
    public static final String CP_APPROVAL_REQUESTED = 'APPROVAL_REQUESTED';
    public static final String CP_BLOCKED = 'BLOCKED';
    public static final String CP_APPROVAL_PROCESS = 'CP_Lead_Approval';
    public static final String CP_APPROVAL_PENDING = 'Pending';
    public static final String CP_APPROVAL_REJECTED = 'Rejected';

    // The Partner Portal Setting (the CP Lead Lost Status, the visit statuses, the backup approvers); tests set their own
    @TestVisible
    private static Partner_Portal_Setting__mdt portalSetting {
        get {
            if (portalSetting == null) {
                portalSetting = Partner_Portal_Setting__mdt.getInstance('Default');
            }
            return portalSetting;
        }
        set;
    }

    private static String settingText(SObjectField field) {
        Object value = portalSetting == null ? null : portalSetting.get(field);
        return value == null || String.isBlank(String.valueOf(value)) ? null : String.valueOf(value).trim();
    }

    private static List<String> settingList(SObjectField field) {
        List<String> values = new List<String>();
        String text = settingText(field);
        if (text != null) {
            for (String value : text.split(',')) {
                if (String.isNotBlank(value)) {
                    values.add(value.trim());
                }
            }
        }
        return values;
    }

    // The backup approvers (Partner Portal Setting usernames, active internal users): the Direct Sales Manager for a
    // Direct Sales lead whose owner has no active manager, and the JKP CP Manager for a CP account whose owner has none;
    // tests set their own
    @TestVisible
    private static Boolean backupApproversLoaded = false;
    @TestVisible
    private static Id backupDirectSalesApprover;
    @TestVisible
    private static Id backupChannelPartnerApprover;

    private static void loadBackupApprovers() {
        if (backupApproversLoaded) {
            return;
        }
        backupApproversLoaded = true;
        String directSales = settingText(Partner_Portal_Setting__mdt.Direct_Sales_Manager_Username__c);
        String channelPartner = settingText(Partner_Portal_Setting__mdt.CP_Manager_Username__c);
        Set<String> usernames = new Set<String>();
        for (String username : new List<String>{ directSales, channelPartner }) {
            if (username != null) {
                usernames.add(username);
            }
        }
        if (usernames.isEmpty()) {
            return;
        }
        // Org-wide: the lead may come from a partner user, who cannot see internal users
        for (User approver : new OrgWide().activeInternalUsersNamed(usernames)) {
            if (approver.Username.equalsIgnoreCase(directSales)) {
                backupDirectSalesApprover = approver.Id;
            }
            if (approver.Username.equalsIgnoreCase(channelPartner)) {
                backupChannelPartnerApprover = approver.Id;
            }
        }
    }

    // What happened to a CP lead: one of the statuses above and the message for the CP
    public class ChannelPartnerOutcome {
        public String status;
        public String message;
        ChannelPartnerOutcome(String status, String message) {
            this.status = status;
            this.message = message;
        }
    }

    // The outcome of each lead of the last insert of up to 200 leads, in Trigger.new order (null for a lead that is not
    // a CP lead), so the caller can show it (the portal inserts one lead); a refused lead's outcome is still here after
    // the DmlException.
    public static List<ChannelPartnerOutcome> channelPartnerOutcomes = new List<ChannelPartnerOutcome>();

    // The Lead Source of channel partner leads: the Partner Portal Setting's Lead Source (Channel Partner)
    @TestVisible
    private static String channelPartnerSource {
        get {
            if (channelPartnerSource == null) {
                List<Partner_Portal_Setting__mdt> settings = [
                    SELECT Lead_Source__c FROM Partner_Portal_Setting__mdt WHERE DeveloperName = 'Default' WITH SYSTEM_MODE LIMIT 1
                ];
                channelPartnerSource = settings.isEmpty() || String.isBlank(settings[0].Lead_Source__c) ? '' : settings[0].Lead_Source__c.trim();
            }
            return channelPartnerSource;
        }
        set;
    }

    // A lead submitted by a channel partner (its Lead Source)
    public static Boolean isChannelPartnerLead(Lead record) {
        return String.isNotBlank(channelPartnerSource) && record.LeadSource == channelPartnerSource;
    }

    // An existing lead that belongs to a channel partner (as opposed to Direct Sales or a referral)
    private static Boolean ownedByChannelPartner(Lead existing) {
        return existing.Channel_Partner__c != null || isChannelPartnerLead(existing);
    }

    // Before insert (the validation rules run right after): each CP lead's outcome.
    public static void prepareChannelPartnerLeads(List<Lead> leads) {
        channelPartnerOutcomes = new List<ChannelPartnerOutcome>();
        Map<Integer, String> keyByIndex = new Map<Integer, String>();
        Set<String> phones = new Set<String>();
        Set<Id> projectIds = new Set<Id>();
        for (Integer i = 0; i < leads.size(); i++) {
            Lead record = leads[i];
            if (!isChannelPartnerLead(record)) {
                channelPartnerOutcomes.add(null);
                continue;
            }
            channelPartnerOutcomes.add(new ChannelPartnerOutcome(CP_CREATED, null));
            if (String.isBlank(record.Email)) {
                record.Email.addError(Label.CP_Lead_Email_Required);
                channelPartnerOutcomes[i] = new ChannelPartnerOutcome(CP_BLOCKED, Label.CP_Lead_Email_Required);
                continue;
            }
            // A blank Mobile Number is the Phone validation rule's to refuse
            if (String.isNotBlank(record.Phone) && !isPhoneNumber(record.Phone)) {
                record.Phone.addError(Label.CP_Lead_Phone_Invalid);
                channelPartnerOutcomes[i] = new ChannelPartnerOutcome(CP_BLOCKED, Label.CP_Lead_Phone_Invalid);
                continue;
            }
            if (record.Status == 'New') {
                record.Status = 'Assigned';
            }
            String phone = normalisedPhoneOf(record.Phone);
            if (String.isNotBlank(phone) && record.Project__c != null) {
                keyByIndex.put(i, phone + '#' + record.Project__c);
                phones.add(phone);
                projectIds.add(record.Project__c);
            }
        }
        if (keyByIndex.isEmpty()) {
            return;
        }

        OrgWide orgWide = new OrgWide();
        Map<String, List<Lead>> duplicatesByKey = orgWide.leadsByPhoneAndProject(phones, projectIds, new Set<Id>());
        // The CP teams of the new leads and of the CP leads they meet, and which of those leads already won the customer
        Set<Id> accountIds = new Set<Id>();
        Set<Id> channelPartnerLeadIds = new Set<Id>();
        for (Integer i : keyByIndex.keySet()) {
            accountIds.add(leads[i].Channel_Partner__c);
        }
        for (List<Lead> duplicates : duplicatesByKey.values()) {
            for (Lead duplicate : duplicates) {
                accountIds.add(duplicate.Channel_Partner__c);
                if (ownedByChannelPartner(duplicate)) {
                    channelPartnerLeadIds.add(duplicate.Id);
                }
            }
        }
        accountIds.remove(null);
        Map<Id, Id> teamByAccount = orgWide.teamsOf(accountIds);
        Set<Id> visitedLeadIds = orgWide.leadsWithVisitStatus(channelPartnerLeadIds,
            settingText(Partner_Portal_Setting__mdt.Completed_Visit_Status__c));
        String lostStatus = settingText(Partner_Portal_Setting__mdt.CP_Lead_Lost_Status__c);

        List<Integer> needApproval = new List<Integer>();
        Map<Integer, Lead> directLeadByIndex = new Map<Integer, Lead>();
        List<Integer> indexes = new List<Integer>(keyByIndex.keySet());
        indexes.sort();
        for (Integer i : indexes) {
            Lead record = leads[i];
            String key = keyByIndex.get(i);
            Id team = teamOf(record.Channel_Partner__c, teamByAccount);
            List<Lead> duplicates = duplicatesByKey.containsKey(key) ? duplicatesByKey.get(key) : new List<Lead>();
            Lead direct;
            Lead sameTeam;
            Boolean anotherTeamWon = false;
            for (Lead duplicate : duplicates) {
                if (team != null && teamOf(duplicate.Channel_Partner__c, teamByAccount) == team) {
                    if (sameTeam == null || duplicate.CP_Approval_Status__c == CP_APPROVAL_PENDING) {
                        sameTeam = duplicate;
                    }
                } else if (!ownedByChannelPartner(duplicate)) {
                    if (direct == null) {
                        direct = duplicate;
                    }
                } else if (duplicate.Status != lostStatus && (duplicate.IsConverted || visitedLeadIds.contains(duplicate.Id))) {
                    anotherTeamWon = true;
                }
            }
            if (sameTeam != null) {
                Boolean ownLead = sameTeam.Channel_Partner__c == record.Channel_Partner__c;
                Boolean waiting = sameTeam.CP_Approval_Status__c == CP_APPROVAL_PENDING;
                refuse(record, i, CP_BLOCKED, ownLead
                    ? (waiting ? Label.CP_Lead_Approval_Pending : Label.CP_Lead_Already_Submitted)
                    : (waiting ? Label.CP_Lead_Team_Approval_Pending : Label.CP_Lead_Team_Already_Submitted));
                continue;
            }
            // Once another CP completed the first successful site visit (or converted the lead), the customer is
            // theirs, whether or not Direct Sales also has it
            if (anotherTeamWon) {
                refuse(record, i, CP_BLOCKED, Label.CP_Lead_Owned_By_Other_CP);
                continue;
            }
            if (direct != null) {
                needApproval.add(i);
                directLeadByIndex.put(i, direct);
            } else if (!duplicates.isEmpty()) {
                channelPartnerOutcomes[i] = new ChannelPartnerOutcome(CP_CREATED_WITH_NOTICE, Label.CP_Lead_Other_CP_Notice);
            }
            // A later lead of this insert for the same customer and project finds this one
            if (!duplicatesByKey.containsKey(key)) {
                duplicatesByKey.put(key, new List<Lead>());
            }
            duplicatesByKey.get(key).add(record);
        }
        if (!needApproval.isEmpty()) {
            holdForApproval(leads, needApproval, directLeadByIndex);
        }
    }

    private static void refuse(Lead record, Integer index, String status, String message) {
        record.addError(message);
        channelPartnerOutcomes[index] = new ChannelPartnerOutcome(status, message);
    }

    // The CP team of a channel partner account: its channel head's account for an executive, its own for a channel head
    private static Id teamOf(Id accountId, Map<Id, Id> teamByAccount) {
        return accountId == null ? null : (teamByAccount.containsKey(accountId) ? teamByAccount.get(accountId) : accountId);
    }

    // Direct/Referral -> CP: the lead is kept back as Pending approval (stage New) with its two approvers and a link to
    // the Direct Sales lead. A missing manager is replaced by the backup approver; refused when there is none either.
    private static void holdForApproval(List<Lead> leads, List<Integer> indexes, Map<Integer, Lead> directLeadByIndex) {
        Set<Id> ownerIds = new Set<Id>();
        Set<Id> accountIds = new Set<Id>();
        for (Integer i : indexes) {
            ownerIds.add(directLeadByIndex.get(i).OwnerId);
            if (leads[i].Channel_Partner__c != null) {
                accountIds.add(leads[i].Channel_Partner__c);
            }
        }
        OrgWide orgWide = new OrgWide();
        Map<Id, Id> managerByUser = orgWide.activeManagersOf(ownerIds);
        Map<Id, Id> managerByAccount = orgWide.accountOwnerManagersOf(accountIds);
        loadBackupApprovers();
        for (Integer i : indexes) {
            Lead record = leads[i];
            Lead direct = directLeadByIndex.get(i);
            Id directSalesApprover = managerByUser.containsKey(direct.OwnerId) ? managerByUser.get(direct.OwnerId) : backupDirectSalesApprover;
            Id channelPartnerApprover = record.Channel_Partner__c == null ? null
                : (managerByAccount.containsKey(record.Channel_Partner__c) ? managerByAccount.get(record.Channel_Partner__c) : backupChannelPartnerApprover);
            if (directSalesApprover == null || channelPartnerApprover == null) {
                refuse(record, i, CP_BLOCKED, Label.CP_Lead_No_Approver);
                continue;
            }
            record.Status = 'New';
            record.CP_Approval_Status__c = CP_APPROVAL_PENDING;
            record.Existing_Direct_Lead__c = direct.Id;
            record.Direct_Sales_Approver__c = directSalesApprover;
            record.CP_Approver__c = channelPartnerApprover;
            channelPartnerOutcomes[i] = new ChannelPartnerOutcome(CP_APPROVAL_REQUESTED, Label.CP_Lead_Approval_Notice);
        }
    }

    // After insert: each lead kept back as Pending approval goes to the CP Lead Approval process. If it cannot be
    // submitted, the lead is not saved.
    public static void submitChannelPartnerApprovals(List<Lead> leads) {
        List<Approval.ProcessSubmitRequest> submissions = new List<Approval.ProcessSubmitRequest>();
        List<Integer> submitted = new List<Integer>();
        for (Integer i = 0; i < leads.size(); i++) {
            Lead record = leads[i];
            if (record.CP_Approval_Status__c != CP_APPROVAL_PENDING || record.hasErrors() || !isChannelPartnerLead(record)) {
                continue;
            }
            Approval.ProcessSubmitRequest submission = new Approval.ProcessSubmitRequest();
            submission.setObjectId(record.Id);
            submission.setProcessDefinitionNameOrId(CP_APPROVAL_PROCESS);
            submission.setSkipEntryCriteria(true);
            submission.setComments('The customer already exists with Direct Sales.');
            submissions.add(submission);
            submitted.add(i);
        }
        List<Approval.ProcessResult> results = LeadSystemOperations.submitForApproval(submissions);
        for (Integer n = 0; n < results.size(); n++) {
            if (!results[n].isSuccess()) {
                Integer i = submitted[n];
                String message = Label.CP_Lead_Approval_Not_Requested + ' (' + results[n].getErrors()[0].getMessage() + ')';
                leads[i].addError(message);
                if (i < channelPartnerOutcomes.size()) {
                    channelPartnerOutcomes[i] = new ChannelPartnerOutcome(CP_BLOCKED, message);
                }
            }
        }
    }

    // CP -> CP: the customer goes to whichever CP completes the first successful site visit. When site visits get the
    // Completed Visit Status (VisitTrigger), each customer (normalised phone + project) of the CP leads visited is
    // settled: the CP lead converted, or else the one whose completed visit to the lead's project came first, wins. The
    // other CP teams' open leads for that customer get the CP Lead Lost Status, their visits still to happen are
    // cancelled, and their partners are emailed. Leads of the winner's own team and converted leads are left; a lead
    // waiting for approval is settled when it is approved (settleApprovedChannelPartnerLeads).
    public static void applyFirstSiteVisitRule(List<Visit__c> visits, Map<Id, Visit__c> oldVisits) {
        String completed = settingText(Partner_Portal_Setting__mdt.Completed_Visit_Status__c);
        String lostStatus = settingText(Partner_Portal_Setting__mdt.CP_Lead_Lost_Status__c);
        if (completed == null || lostStatus == null) {
            return;
        }
        // The projects visited, by lead (null: a visit without a project, which counts for the lead's project)
        Map<Id, Set<Id>> projectsVisitedByLead = new Map<Id, Set<Id>>();
        for (Visit__c visit : visits) {
            Visit__c before = oldVisits == null ? null : oldVisits.get(visit.Id);
            if (visit.Lead__c != null && visit.Status__c == completed && (before == null || before.Status__c != completed)) {
                if (!projectsVisitedByLead.containsKey(visit.Lead__c)) {
                    projectsVisitedByLead.put(visit.Lead__c, new Set<Id>());
                }
                projectsVisitedByLead.get(visit.Lead__c).add(visit.Project__c);
            }
        }
        if (projectsVisitedByLead.isEmpty()) {
            return;
        }

        // The customers of the CP leads whose own project was just visited
        OrgWide orgWide = new OrgWide();
        Customers visited = new Customers();
        for (Lead visitedLead : orgWide.leadsWithIds(projectsVisitedByLead.keySet())) {
            Set<Id> projects = projectsVisitedByLead.get(visitedLead.Id);
            if (ownedByChannelPartner(visitedLead) && (projects.contains(null) || projects.contains(visitedLead.Project__c))) {
                visited.add(visitedLead);
            }
        }
        if (visited.keys.isEmpty()) {
            return;
        }

        // Each customer's CP leads still in the running
        Map<String, List<Lead>> leadsByKey = orgWide.leadsByPhoneAndProject(visited.phones, visited.projectIds, new Set<Id>());
        Map<String, List<Lead>> runningByKey = new Map<String, List<Lead>>();
        Set<Id> runningIds = new Set<Id>();
        Set<Id> accountIds = new Set<Id>();
        for (String key : visited.keys) {
            List<Lead> running = new List<Lead>();
            for (Lead candidate : leadsByKey.containsKey(key) ? leadsByKey.get(key) : new List<Lead>()) {
                if (ownedByChannelPartner(candidate) && candidate.Status != lostStatus && candidate.CP_Approval_Status__c != CP_APPROVAL_PENDING) {
                    running.add(candidate);
                    runningIds.add(candidate.Id);
                    accountIds.add(candidate.Channel_Partner__c);
                }
            }
            if (running.size() > 1) {
                runningByKey.put(key, running);
            }
        }
        if (runningByKey.isEmpty()) {
            return;
        }
        accountIds.remove(null);
        Map<Id, Id> teamByAccount = orgWide.teamsOf(accountIds);
        Map<Id, Datetime> firstVisitByLead = orgWide.firstVisits(runningIds, completed);

        Map<Id, Lead> losers = new Map<Id, Lead>();
        for (List<Lead> running : runningByKey.values()) {
            Lead winner = winnerOf(running, firstVisitByLead);
            if (winner == null) {
                continue;
            }
            Id winningTeam = teamOf(winner.Channel_Partner__c, teamByAccount);
            for (Lead candidate : running) {
                Boolean winnersTeam = winningTeam != null && teamOf(candidate.Channel_Partner__c, teamByAccount) == winningTeam;
                if (candidate.Id != winner.Id && !candidate.IsConverted && !winnersTeam) {
                    losers.put(candidate.Id, new Lead(Id = candidate.Id, Status = lostStatus));
                }
            }
        }
        closeLostLeads(losers.values(), orgWide);
    }

    // A converted lead settles its customer too: the other CP teams' open leads for the same customer (normalised
    // phone + project, however the phone was typed) get the CP Lead Lost Status, their visits still to happen are
    // cancelled and their partners are emailed. After update (LeadTrigger), as a lead is converted; a lead waiting for
    // approval is settled when it is approved.
    public static void applyConversionRule(List<Lead> leads, Map<Id, Lead> oldLeads) {
        String lostStatus = settingText(Partner_Portal_Setting__mdt.CP_Lead_Lost_Status__c);
        if (lostStatus == null || oldLeads == null) {
            return;
        }
        Customers converted = new Customers();
        Map<String, List<Lead>> convertedByKey = new Map<String, List<Lead>>();
        for (Lead record : leads) {
            Lead before = oldLeads.get(record.Id);
            if (record.IsConverted && before != null && !before.IsConverted) {
                String key = converted.add(record);
                if (key != null) {
                    if (!convertedByKey.containsKey(key)) {
                        convertedByKey.put(key, new List<Lead>());
                    }
                    convertedByKey.get(key).add(record);
                }
            }
        }
        if (converted.keys.isEmpty()) {
            return;
        }
        OrgWide orgWide = new OrgWide();
        Map<String, List<Lead>> leadsByKey = orgWide.leadsByPhoneAndProject(converted.phones, converted.projectIds, new Set<Id>());
        Set<Id> accountIds = new Set<Id>();
        for (Lead record : leads) {
            accountIds.add(record.Channel_Partner__c);
        }
        for (List<Lead> customerLeads : leadsByKey.values()) {
            for (Lead candidate : customerLeads) {
                accountIds.add(candidate.Channel_Partner__c);
            }
        }
        accountIds.remove(null);
        Map<Id, Id> teamByAccount = orgWide.teamsOf(accountIds);
        Map<Id, Lead> losers = new Map<Id, Lead>();
        for (String key : converted.keys) {
            // The teams of the CP leads converted (none for a Direct Sales lead: every CP lead loses)
            Set<Id> winningTeams = new Set<Id>();
            Set<Id> convertedIds = new Set<Id>();
            for (Lead winner : convertedByKey.get(key)) {
                convertedIds.add(winner.Id);
                if (ownedByChannelPartner(winner) && winner.Channel_Partner__c != null) {
                    winningTeams.add(teamOf(winner.Channel_Partner__c, teamByAccount));
                }
            }
            for (Lead candidate : leadsByKey.containsKey(key) ? leadsByKey.get(key) : new List<Lead>()) {
                Boolean open = ownedByChannelPartner(candidate) && !candidate.IsConverted && candidate.Status != lostStatus
                    && candidate.CP_Approval_Status__c != CP_APPROVAL_PENDING && !convertedIds.contains(candidate.Id);
                if (open && !winningTeams.contains(teamOf(candidate.Channel_Partner__c, teamByAccount))) {
                    losers.put(candidate.Id, new Lead(Id = candidate.Id, Status = lostStatus));
                }
            }
        }
        closeLostLeads(losers.values(), orgWide);
    }

    // A CP lead waiting for approval is not settled while it waits (it is locked). When the managers approve it, it gets
    // the CP Lead Lost Status instead of Assigned if another CP team won the customer meanwhile (a completed visit to
    // the project, or a conversion). Before update (LeadTrigger), as the approval's field updates save the lead; then
    // closeLeadsLostOnApproval cancels its open visits and emails the partner.
    public static void settleApprovedChannelPartnerLeads(List<Lead> leads, Map<Id, Lead> oldLeads) {
        String lostStatus = settingText(Partner_Portal_Setting__mdt.CP_Lead_Lost_Status__c);
        if (lostStatus == null || oldLeads == null) {
            return;
        }
        Customers approved = new Customers();
        List<Lead> justApproved = new List<Lead>();
        for (Lead record : leads) {
            Lead before = oldLeads.get(record.Id);
            if (before != null && before.CP_Approval_Status__c == CP_APPROVAL_PENDING && record.CP_Approval_Status__c != CP_APPROVAL_PENDING
                    && record.CP_Approval_Status__c != CP_APPROVAL_REJECTED && isChannelPartnerLead(record) && approved.add(record) != null) {
                justApproved.add(record);
            }
        }
        if (justApproved.isEmpty()) {
            return;
        }
        OrgWide orgWide = new OrgWide();
        Set<Id> excluded = new Map<Id, Lead>(justApproved).keySet();
        Map<String, List<Lead>> leadsByKey = orgWide.leadsByPhoneAndProject(approved.phones, approved.projectIds, excluded);
        Set<Id> accountIds = new Set<Id>();
        Set<Id> channelPartnerLeadIds = new Set<Id>();
        for (Lead record : justApproved) {
            accountIds.add(record.Channel_Partner__c);
        }
        for (List<Lead> customerLeads : leadsByKey.values()) {
            for (Lead candidate : customerLeads) {
                accountIds.add(candidate.Channel_Partner__c);
                if (ownedByChannelPartner(candidate)) {
                    channelPartnerLeadIds.add(candidate.Id);
                }
            }
        }
        accountIds.remove(null);
        Map<Id, Id> teamByAccount = orgWide.teamsOf(accountIds);
        Set<Id> visitedLeadIds = orgWide.leadsWithVisitStatus(channelPartnerLeadIds,
            settingText(Partner_Portal_Setting__mdt.Completed_Visit_Status__c));
        for (Lead record : justApproved) {
            String key = approved.keyOf(record);
            Id team = teamOf(record.Channel_Partner__c, teamByAccount);
            for (Lead candidate : leadsByKey.containsKey(key) ? leadsByKey.get(key) : new List<Lead>()) {
                Boolean otherTeam = ownedByChannelPartner(candidate) && (team == null || teamOf(candidate.Channel_Partner__c, teamByAccount) != team);
                if (otherTeam && candidate.Status != lostStatus && (candidate.IsConverted || visitedLeadIds.contains(candidate.Id))) {
                    record.Status = lostStatus;
                    break;
                }
            }
        }
    }

    // After the approval saved a CP lead as lost (settleApprovedChannelPartnerLeads): its open visits are cancelled and
    // its partner is emailed
    public static void closeLeadsLostOnApproval(List<Lead> leads, Map<Id, Lead> oldLeads) {
        String lostStatus = settingText(Partner_Portal_Setting__mdt.CP_Lead_Lost_Status__c);
        if (lostStatus == null || oldLeads == null) {
            return;
        }
        Set<Id> lost = new Set<Id>();
        for (Lead record : leads) {
            Lead before = oldLeads.get(record.Id);
            if (before != null && before.CP_Approval_Status__c == CP_APPROVAL_PENDING && record.CP_Approval_Status__c != CP_APPROVAL_PENDING
                    && record.Status == lostStatus && before.Status != lostStatus) {
                lost.add(record.Id);
            }
        }
        afterLeadsLost(lost, new OrgWide());
    }

    // A lead whose customer went to another (the CP Lead Lost Status) stays closed: completing one of its site visits
    // does not reopen it as Visited (the Freeze status change rule would refuse the whole save). Before update.
    public static void keepLostLeadsClosed(List<Lead> leads, Map<Id, Lead> oldLeads) {
        String lostStatus = settingText(Partner_Portal_Setting__mdt.CP_Lead_Lost_Status__c);
        if (lostStatus == null || oldLeads == null) {
            return;
        }
        for (Lead record : leads) {
            Lead before = oldLeads.get(record.Id);
            if (before != null && before.Status == lostStatus && record.Status == VISITED_STATUS) {
                record.Status = lostStatus;
            }
        }
    }

    private static final String VISITED_STATUS = 'Visited';

    // Saves these leads with the CP Lead Lost Status; then cancels their open visits and emails their partners. A lead
    // that cannot be closed does not stop the others (nor undo the visit or conversion that settled the customer).
    private static void closeLostLeads(List<Lead> losers, OrgWide orgWide) {
        if (losers.isEmpty()) {
            return;
        }
        Set<Id> closed = new Set<Id>();
        List<Database.SaveResult> results = orgWide.updateLeads(losers);
        for (Integer n = 0; n < results.size(); n++) {
            if (results[n].isSuccess()) {
                closed.add(losers[n].Id);
            } else {
                System.debug(LoggingLevel.ERROR, 'CP lead not closed after another CP won the customer: ' + results[n].getErrors());
            }
        }
        afterLeadsLost(closed, orgWide);
    }

    private static void afterLeadsLost(Set<Id> lost, OrgWide orgWide) {
        if (lost.isEmpty()) {
            return;
        }
        String cancelled = settingText(Partner_Portal_Setting__mdt.Cancelled_Visit_Status__c);
        List<String> open = settingList(Partner_Portal_Setting__mdt.Open_Visit_Statuses__c);
        if (cancelled != null && !open.isEmpty()) {
            orgWide.cancelVisits(lost, open, cancelled, Label.CP_Lead_Visit_Cancelled_Reason);
        }
        CPLeadOwnershipNotifier.notifyLater(lost);
    }

    // The customers (normalised phone + project) of some leads
    private class Customers {
        final Set<String> keys = new Set<String>();
        final Set<String> phones = new Set<String>();
        final Set<Id> projectIds = new Set<Id>();

        // Adds the lead's customer; its key, or null for a lead without a phone or project
        String add(Lead record) {
            String key = keyOf(record);
            if (key != null) {
                keys.add(key);
                phones.add(key.substringBefore('#'));
                projectIds.add(record.Project__c);
            }
            return key;
        }

        String keyOf(Lead record) {
            String phone = String.isNotBlank(record.Normalised_Phone__c) ? record.Normalised_Phone__c : normalisedPhoneOf(record.Phone);
            return String.isBlank(phone) || record.Project__c == null ? null : phone + '#' + record.Project__c;
        }
    }

    // The CP lead that won its customer: a converted one, else the one whose site visit was completed first
    private static Lead winnerOf(List<Lead> running, Map<Id, Datetime> firstVisitByLead) {
        Lead winner;
        Datetime first;
        for (Lead candidate : running) {
            if (candidate.IsConverted) {
                return candidate;
            }
            Datetime visited = firstVisitByLead.get(candidate.Id);
            if (visited != null && (first == null || visited < first)) {
                winner = candidate;
                first = visited;
            }
        }
        return winner;
    }

    // Org-wide lookups the CP rules need whoever submits the lead (a partner user cannot see other partners' or
    // Direct Sales' leads, or other users' managers)
    private without sharing class OrgWide {
        void insertRecords(List<SObject> records) {
            Database.insert(records, AccessLevel.SYSTEM_MODE);
        }


        // The leads of these projects whose normalised phone is one of these, by phone + '#' + project, oldest first;
        // a lead saved without a normalised phone is matched on its phone
        Map<String, List<Lead>> leadsByPhoneAndProject(Set<String> phones, Set<Id> projectIds, Set<Id> excluded) {
            Map<String, List<Lead>> byKey = new Map<String, List<Lead>>();
            for (Lead existing : [
                SELECT Id, Phone, Normalised_Phone__c, Project__c, IsConverted, ConvertedOpportunityId, OwnerId, LeadSource,
                       Lead_Sub_Source__c, Channel_Partner__c, CP_Approval_Status__c, Status
                FROM Lead
                WHERE Project__c IN :projectIds AND Id NOT IN :excluded AND CP_Approval_Status__c != :CP_APPROVAL_REJECTED
                  AND (Normalised_Phone__c IN :phones OR (Normalised_Phone__c = null AND Phone != null))
                WITH SYSTEM_MODE
                ORDER BY CreatedDate ASC, Id ASC
            ]) {
                String phone = String.isNotBlank(existing.Normalised_Phone__c) ? existing.Normalised_Phone__c : normalisedPhoneOf(existing.Phone);
                if (!phones.contains(phone)) {
                    continue;
                }
                String key = phone + '#' + existing.Project__c;
                if (!byKey.containsKey(key)) {
                    byKey.put(key, new List<Lead>());
                }
                byKey.get(key).add(existing);
            }
            return byKey;
        }

        // The team's duplicate check (checkDuplicateLead): leads with one of these normalised phones in these projects,
        // but not a CP lead the managers rejected (to the chart, no lead was created for that CP)
        List<Lead> leadsWithPhoneInProjects(Set<String> phones, Set<Id> projectIds) {
            return [
                SELECT Id, Normalised_Phone__c, IsConverted, Project__c, ConvertedOpportunityId, Multi_Channel_Engaged__c,
                       LeadSource, Lead_Sub_Source__c, CreatedDate, Channel_Partner__c
                FROM Lead
                WHERE Normalised_Phone__c IN :phones AND Project__c IN :projectIds AND CP_Approval_Status__c != :CP_APPROVAL_REJECTED
                WITH SYSTEM_MODE
                ORDER BY CreatedDate ASC, Id ASC
            ];
        }

        // The active internal users with these usernames
        List<User> activeInternalUsersNamed(Set<String> usernames) {
            return [
                SELECT Id, Username FROM User WHERE Username IN :usernames AND IsActive = true AND UserType = 'Standard' WITH SYSTEM_MODE
            ];
        }

        // The CP team of each channel partner account: its Channel Head, or itself for a channel head
        Map<Id, Id> teamsOf(Set<Id> accountIds) {
            Map<Id, Id> teams = new Map<Id, Id>();
            for (Account partner : [SELECT Id, Channel_Head__c FROM Account WHERE Id IN :accountIds WITH SYSTEM_MODE]) {
                teams.put(partner.Id, partner.Channel_Head__c != null ? partner.Channel_Head__c : partner.Id);
            }
            return teams;
        }

        // The leads among these with a site visit of this status to their own project (or to no project)
        Set<Id> leadsWithVisitStatus(Set<Id> leadIds, String status) {
            Set<Id> visited = new Set<Id>();
            if (status == null || leadIds.isEmpty()) {
                return visited;
            }
            for (Visit__c visit : [
                SELECT Lead__c, Project__c, Lead__r.Project__c FROM Visit__c WHERE Lead__c IN :leadIds AND Status__c = :status
                WITH SYSTEM_MODE
            ]) {
                if (visit.Project__c == null || visit.Project__c == visit.Lead__r.Project__c) {
                    visited.add(visit.Lead__c);
                }
            }
            return visited;
        }

        List<Lead> leadsWithIds(Set<Id> leadIds) {
            return [
                SELECT Id, Phone, Normalised_Phone__c, Project__c, LeadSource, Channel_Partner__c FROM Lead WHERE Id IN :leadIds
                WITH SYSTEM_MODE
            ];
        }

        // When each lead's first site visit of this status to its own project (or to no project) took place: when it
        // was completed, or else on its visit date, or else when it was recorded
        Map<Id, Datetime> firstVisits(Set<Id> leadIds, String status) {
            Map<Id, Datetime> first = new Map<Id, Datetime>();
            for (Visit__c visit : [
                SELECT Lead__c, Project__c, Lead__r.Project__c, Completed_At_Date_Time__c, Visit_Date__c, CreatedDate FROM Visit__c
                WHERE Lead__c IN :leadIds AND Status__c = :status
                WITH SYSTEM_MODE
            ]) {
                if (visit.Project__c != null && visit.Project__c != visit.Lead__r.Project__c) {
                    continue;
                }
                Datetime at = visit.Completed_At_Date_Time__c != null ? visit.Completed_At_Date_Time__c
                    : (visit.Visit_Date__c != null ? Datetime.newInstance(visit.Visit_Date__c, Time.newInstance(0, 0, 0, 0)) : visit.CreatedDate);
                if (!first.containsKey(visit.Lead__c) || at < first.get(visit.Lead__c)) {
                    first.put(visit.Lead__c, at);
                }
            }
            return first;
        }

        // Saves these leads, each on its own (the user whose visit or conversion settled the customer may not share them)
        List<Database.SaveResult> updateLeads(List<Lead> leads) {
            return Database.update(leads, false, AccessLevel.SYSTEM_MODE);
        }

        // Cancels these leads' site visits still to happen, with the reason
        void cancelVisits(Set<Id> leadIds, List<String> openStatuses, String cancelledStatus, String reason) {
            List<Visit__c> visits = [
                SELECT Id FROM Visit__c WHERE Lead__c IN :leadIds AND Status__c IN :openStatuses WITH SYSTEM_MODE
            ];
            for (Visit__c visit : visits) {
                visit.Status__c = cancelledStatus;
                visit.Reason_of_Cancellation__c = reason;
            }
            for (Database.SaveResult result : Database.update(visits, false, AccessLevel.SYSTEM_MODE)) {
                if (!result.isSuccess()) {
                    System.debug(LoggingLevel.ERROR, 'Site visit not cancelled: ' + result.getErrors());
                }
            }
        }

        // Each user's manager, when the manager is an active user
        Map<Id, Id> activeManagersOf(Set<Id> userIds) {
            Map<Id, Id> managers = new Map<Id, Id>();
            for (User owner : [
                SELECT Id, ManagerId FROM User
                WHERE Id IN :userIds AND ManagerId != null AND Manager.IsActive = true
                WITH SYSTEM_MODE
            ]) {
                managers.put(owner.Id, owner.ManagerId);
            }
            return managers;
        }

        // The manager of each account's owner, when that manager is an active user
        Map<Id, Id> accountOwnerManagersOf(Set<Id> accountIds) {
            Map<Id, Id> managers = new Map<Id, Id>();
            for (Account partner : [
                SELECT Id, Owner.ManagerId FROM Account
                WHERE Id IN :accountIds AND Owner.ManagerId != null AND Owner.Manager.IsActive = true
                WITH SYSTEM_MODE
            ]) {
                managers.put(partner.Id, partner.Owner.ManagerId);
            }
            return managers;
        }
    }
}