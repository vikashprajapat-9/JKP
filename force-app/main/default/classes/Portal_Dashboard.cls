public class Portal_Dashboard {

	@AuraEnabled(cacheable=true)
	public static void getUser(Id recordId) {
		user u=[SELECT Id,Name from user where Id=:recordId LIMIT 1];
		
	}

}