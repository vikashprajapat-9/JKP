public class LeadLogicController {

	public static void calculateLeadScore(List<Lead> leads) {
        if(leads.isEmpty()){
            return;
        }
        Set<String> values = new Set<String>();
        for(Lead l : leads){
            if(String.isNotBlank(l.Designation__c))
                values.add(l.Designation__c);

            if(String.isNotBlank(l.Purchase_Type__c))
                values.add(l.Purchase_Type__c);

            if(String.isNotBlank(l.Time_to_Purchase__c))
                values.add(l.Time_to_Purchase__c);

            if(String.isNotBlank(l.Budget_Aligned__c))
                values.add(l.Budget_Aligned__c);
        }
        Map<String, Decimal> scoreMap = new Map<String, Decimal>();
		List<Lead_Priority_Configs__c> priorityConfigs = [ SELECT Min_Score__c, Max_Score__c, Priority__c FROM Lead_Priority_Configs__c WHERE Active__c = true ORDER BY Min_Score__c ASC];
        for(Lead_Score_Config__c cfg : [ SELECT Field_API_Name__c,Picklist_Value__c,Score__c,Active__c FROM Lead_Score_Config__c WHERE Active__c = true AND Picklist_Value__c IN :values
        ]){
            String key = cfg.Field_API_Name__c + '-' + cfg.Picklist_Value__c;
            scoreMap.put(key,cfg.Score__c);
        }
        for(Lead l : leads){
			if (l.Lead_Sub_Source__c == 'Website Forms') {
				l.Lead_Priority__c = 'Hot';
			}
			if (l.LeadSource != 'Digital Source' || l.Lead_Sub_Source__c == 'Website Forms') {
                l.Lead_Score__c = 0;
                continue;
            }
			
            Decimal totalScore = 0;
            totalScore += getScore(scoreMap,'Designation__c',l.Designation__c);
            totalScore += getScore(scoreMap,'Purchase_Type__c',l.Purchase_Type__c);
            totalScore += getScore(scoreMap,'Time_to_Purchase__c',l.Time_to_Purchase__c);
            totalScore += getScore(scoreMap,'Budget_Alignment__c',l.Budget_Aligned__c);
            l.Lead_Score__c = totalScore;
			for (Lead_Priority_Configs__c cfg : priorityConfigs) {
				if (totalScore >= cfg.Min_Score__c && totalScore <= cfg.Max_Score__c) {
					l.Lead_Priority__c = cfg.Priority__c;
					break;
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
                l.Lead_Priority__c != 'Hot' &&
                l.Lead_Priority__c != 'Warm'
            ) {
                l.addError('Manually created leads must be classified as Hot or Warm.');
            }
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
    // public static void checkDuplicateLead(List<Lead> leads) {
    //     Set<String> phones = new Set<String>();
    //     Set<Id> projectIds = new Set<Id>();
    //     for (Lead l : leads) {
    //         if (String.isNotBlank(l.Normalised_Phone__c)) {
    //             phones.add(l.Normalised_Phone__c);
    //         }
    //         if (l.Project__c != null) {
    //             projectIds.add(l.Project__c);
    //         }
    //     }
    //     if (phones.isEmpty() || projectIds.isEmpty()) {
    //         return;
    //     }
    //     List<Lead> existingLeads = [ SELECT Id,Normalised_Phone__c,Project__c,Multi_Channel_Engaged__c,LeadSource,Lead_Sub_Source__c FROM Lead WHERE Normalised_Phone__c IN :phones AND Project__c IN :projectIds ];
    //     Map<String,Lead> duplicateMap = new Map<String,Lead>();
    //     for(Lead l : existingLeads){
    //         duplicateMap.put(l.Normalised_Phone__c+'#'+String.valueOf(l.Project__c),  l );
    //     }
    //     List<Re_Enquiry__c> reEnquiries = new List<Re_Enquiry__c>();
    //     List<Lead> leadsToUpdate = new List<Lead>();

    //     for(Lead newLead : leads){
    //         String key =  newLead.Normalised_Phone__c+'#'+String.valueOf(newLead.Project__c);
    //         if(!duplicateMap.containsKey(key))
    //             continue;
    //         Lead existingLead = duplicateMap.get(key);
    //         Boolean existingCP = isChannelPartner(existingLead.LeadSource);
    //         Boolean incomingCP = isChannelPartner(newLead.LeadSource);
    //         //----------------------------------------------------
    //         // CASE 1
    //         // Existing = Digital/Manual
    //         // Incoming = Digital/Manual
    //         //----------------------------------------------------

    //         if(!existingCP && !incomingCP){
    //             Re_Enquiry__c enquiry = new Re_Enquiry__c();
    //             enquiry.Lead__c = existingLead.Id;
    //             enquiry.Re_Enquiry_Source__c = newLead.LeadSource;
    //             enquiry.Re_Enquiry_Sub_Source__c = newLead.Lead_Sub_Source__c;
    //             enquiry.Enquiry_DateTime__c = System.now();
    //             enquiry.Source_Match__c =isSameSource(existingLead,newLead)? 'Same Source': 'New Source';
    //             enquiry.Sub_Source_Match__c = isSameSubSource(existingLead,newLead) ? 'Same Sub Source': 'New Sub Source';
    //             reEnquiries.add(enquiry);
    //             if(!isSameSource(existingLead,newLead)){
    //                 existingLead.Multi_Channel_Engaged__c = true;
    //                 leadsToUpdate.add(existingLead);
    //             }
    //             newLead.addError( 'Lead already exists. Re-Enquiry has been created.' );
    //         }
    //         //----------------------------------------------------
    //         // CASE 2
    //         // Existing CP
    //         // Incoming CP
    //         //----------------------------------------------------
    //         else if(existingCP && incomingCP){
    //           //  newLead.addError(  'Lead already exists with another CP — ownership goes to whichever CP completes the first successful Site Visit.');
    //         }

    //         //----------------------------------------------------
    //         // CASE 3
    //         // Existing Digital/Manaual
    //         // Incoming CP
    //         //----------------------------------------------------
    //         else if(!existingCP && incomingCP){
    //             newLead.addError('Lead requires approval because an existing Digital/Manual Lead is present.' );
    //         }
    //         //----------------------------------------------------
    //         // CASE 4
    //         // Existing CP
    //         // Incoming Digital/Manual
    //         //----------------------------------------------------
    //         else if(existingCP && !incomingCP){
    //             Integer lockDays = 60;
    //             Date expiry = existingLead.CreatedDate.date().addDays(lockDays);
    //             if(Date.today() <= expiry){
    //                 newLead.addError( 'Lead cannot be created because Channel Partner lock-in is active.');
    //             }
    //         }
    //     }
    //     if(!reEnquiries.isEmpty())
    //         insert reEnquiries;

    //     if(!leadsToUpdate.isEmpty())
    //         update leadsToUpdate;

    //     }

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
        List<Lead> existingLeads = [ SELECT Id,Normalised_Phone__c,Project__c,Multi_Channel_Engaged__c,LeadSource,Lead_Sub_Source__c,CreatedDate FROM Lead WHERE Normalised_Phone__c IN :phones AND Project__c IN :projectIds ];
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
            if(!existingCP && !incomingCP){
                events.add(new Lead_Duplicate_Event__e(
                    Existing_Lead_Id__c    = existingLead.Id,
                    New_Lead_Source__c     = newLead.LeadSource,
                    New_Lead_Sub_Source__c = newLead.Lead_Sub_Source__c
                ));
                newLead.addError( 'Lead already exists. Re-Enquiry has been created.' );
            }
            //----------------------------------------------------
            // CASE 2
            // Existing CP
            // Incoming CP
            //----------------------------------------------------
            else if(existingCP && incomingCP){
              //  newLead.addError(  'Lead already exists with another CP — ownership goes to whichever CP completes the first successful Site Visit.');
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

}