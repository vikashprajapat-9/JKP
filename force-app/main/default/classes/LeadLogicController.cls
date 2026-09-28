public class LeadLogicController {

	public static void calculateLeadScore(List<Lead> leads) {
        if(leads.isEmpty()){
            return;
        }
        List<Lead_Score_Field__mdt> fieldConfigs = [
            SELECT Field_API_Name__c
            FROM Lead_Score_Field__mdt
            WHERE Active__c = true
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
                                                            ORDER BY Min_Score__c ASC
                                                        ];
        for(Lead_Score_Config__c cfg : [
                                        SELECT Field_API_Name__c,Picklist_Value__c,Score__c,Active__c 
                                        FROM Lead_Score_Config__c 
                                        WHERE Active__c = true 
                                        AND Picklist_Value__c IN :values
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
            String phone = l.Phone;
            phone = phone.replaceAll('[^0-9]', '');
            if (phone.length() > 10) {
                phone = phone.substring(phone.length() - 10);
            }
            l.Normalised_Phone__c = phone;
        }
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
                                                    FROM Lead_Assignment_History__c WHERE Lead__c IN :leadIds  ORDER BY CreatedDate DESC
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
            insert historyList;
        }
    }
    
    private static Boolean isChannelPartner(String source){
        return source != null && source.equalsIgnoreCase('Channel Partner Source');
    }

    private static Boolean isSameSource(Lead existingLead, Lead newLead){
        return existingLead.LeadSource == newLead.LeadSource;
    }

    private static Boolean isSameSubSource(Lead existingLead, Lead newLead){
        return existingLead.Lead_Sub_Source__c == newLead.Lead_Sub_Source__c;
    }
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
        List<Lead> existingLeads = [ SELECT Id,Normalised_Phone__c,IsConverted,Project__c,ConvertedOpportunityId,Multi_Channel_Engaged__c,LeadSource,Lead_Sub_Source__c,CreatedDate FROM Lead WHERE Normalised_Phone__c IN :phones AND Project__c IN :projectIds ];
        Map<String,Lead> duplicateMap = new Map<String,Lead>();
        for(Lead l : existingLeads){
            duplicateMap.put(l.Normalised_Phone__c+'#'+String.valueOf(l.Project__c),  l );
        }
        List<Lead_Duplicate_Event__e> events = new List<Lead_Duplicate_Event__e>();
        for(Lead newLead : leads){
            String key =  newLead.Normalised_Phone__c+'#'+String.valueOf(newLead.Project__c);
            if(!duplicateMap.containsKey(key))
                continue;
            Lead existingLead = duplicateMap.get(key);
            Boolean existingCP = isChannelPartner(existingLead.LeadSource);
            Boolean incomingCP = isChannelPartner(newLead.LeadSource);
            //----------------------------------------------------
            // CASE 1
            // Existing = Digital/Manual
            // Incoming = Digital/Manual
            //----------------------------------------------------
            if (!existingCP && !incomingCP) {

                Lead_Duplicate_Event__e eventRec = new Lead_Duplicate_Event__e();

                if(existingLead.IsConverted){
                    eventRec.Existing_Opportunity_Id__c = existingLead.ConvertedOpportunityId;
                }else{
                    eventRec.Existing_Lead_Id__c = existingLead.Id;
                }
                eventRec.New_Lead_Source__c = newLead.LeadSource;
                eventRec.New_Lead_Sub_Source__c = newLead.Lead_Sub_Source__c;
                events.add(eventRec);
                newLead.addError('Lead already exists. Re-Enquiry has been created.');
            }
            //----------------------------------------------------
            // CASE 2
            // Existing CP
            // Incoming CP
            //----------------------------------------------------
            else if(existingCP && incomingCP){
              //  newLead.addError(  'Lead already exists with another CP — ownership goes to whichever CP completes the first successful Site Visit.');
                continue;
            }
            //----------------------------------------------------
            // CASE 3
            // Existing Digital/Manaual
            // Incoming CP
            //----------------------------------------------------
            else if(!existingCP && incomingCP){
               // newLead.addError('Lead requires approval because an existing Digital/Manual Lead is present.' );
            }
            //----------------------------------------------------
            // CASE 4
            // Existing CP
            // Incoming Digital/Manual
            //----------------------------------------------------
            else if(existingCP && !incomingCP){
                Integer lockDays = 60;
                Date expiry = existingLead.CreatedDate.date().addDays(lockDays);
                if(Date.today() <= expiry){
                    newLead.addError( 'Lead cannot be created because Channel Partner lock-in is active.');
                }
            }
        }
        if(!events.isEmpty()){
            EventBus.publish(events);
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
            LIMIT 1
        ];
        if (template.isEmpty()) {
            return;
        }
        List<OrgWideEmailAddress> oweaList = [
            SELECT Id
            FROM OrgWideEmailAddress
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        Map<Id, User> usersMap = new Map<Id, User>([
            SELECT Id, Name, Email
            FROM User
            WHERE Id IN :userIdSet
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
                tk.ActivityDate = l.Lead_Assigned_Date_Time__c.date();
                tk.Description = 'Follow-up generated after Lead Assignment.';
                tasksToInsert.add(tk);
            } else {
                Task tk = new Task();
                tk.Subject = 'Contact the lead within 4 hrs';
                tk.Status = 'Not Started';
                tk.Priority = 'Normal';
                tk.OwnerId = l.OwnerId;
                tk.WhoId = l.Id;
                tk.ActivityDate = l.Lead_Assigned_Date_Time__c.date();
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
            insert tasksToInsert;
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
}