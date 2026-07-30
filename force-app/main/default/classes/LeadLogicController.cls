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

}