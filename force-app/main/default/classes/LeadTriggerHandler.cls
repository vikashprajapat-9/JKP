/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : LeadTriggerHandler
 * Author          : <YourName>
 * Created Date    : Jul 27, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jul 27, 2026
 * Description     : This class implements for......
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jul 27, 2026  │ <YourName>   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

public class LeadTriggerHandler {
	public static void performInitialOperations(List<Lead> newLeads, Map<Id,Lead> oldMap) {
		if(newLeads.isEmpty()) {
			System.debug('Lead List is Empty!');
			return;
		}
		List<Lead> leadsToScore = new List<Lead>();
		for(Lead ld : newLeads) {
			if(
				(ld.Lead_Sub_Source__c != 'Website Forms') && 
				(ld.LeadSource != 'Walk In') && 
				(
					!oldMap.containsKey(ld.Id) || 
					(
						ld.Designation__c != oldMap.get(ld.Id).Designation__c || 
						ld.Purchase_Type__c != oldMap.get(ld.Id).Purchase_Type__c || 
						ld.Time_to_Purchase__c != oldMap.get(ld.Id).Time_to_Purchase__c || 
						ld.Budget_Aligned__c != oldMap.get(ld.Id).Budget_Aligned__c
					)
				)
			) {
				leadsToScore.add(ld);
			}
		}
		if(!leadsToScore.isEmpty()) {
			LeadLogicController.calculateLeadScore(leadsToScore);
		}
	}
}