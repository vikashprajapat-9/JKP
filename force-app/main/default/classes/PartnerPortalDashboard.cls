public class PartnerPortalDashboard {

	@AuraEnabled(cacheable=true)
	public static integer getLeaddetail() {
		return [SELECT count() from Lead ];
	
	}
	@AuraEnabled(cacheable=true)
	public static integer getSitedetail() {
		return [SELECT count() from Visit__c  ];
	
	}
		@AuraEnabled(cacheable=true)
	public static String getCurrentUser() {
		return [SELECT Name from user where Id=:UserInfo.getUserId()].Name;
	
	}

}