/**
* Author : VamsiKrishna
**/

public class OneDriveService {

	private string clientId {get;set;}
    private string clientSecret {get;set;}
    private string scope {get;set;}
    private string grantType{get;set;}
    private string tokenUrl{get;set;}
    private string redirectUrl  {get;set;}
    private string graphUrl{get;set;}
    private string authUrl{get;set;}
    private string adminConsentUrl{get;set;}
    
    private static OneDriveAuthSetting__mdt setting;
    
    public OneDriveService(){
        if(setting==null){
            setting= OneDriveSetting;
        }
        if(setting!=null){
            clientId=setting.ClientID__c;
            clientSecret=setting.ClientSecret__c;
            scope=setting.Scope__c;
            redirectUrl=setting.RedirectUrl__c;
            grantType=setting.AuthGrantType__c;
            authUrl=setting.AuthEndpoint__c.replace('{tenant}', setting.TenantId__c); 
            tokenUrl=setting.TokenUrl__c.replace('{tenant}', setting.TenantId__c); 
        }
    }

	public static OneDriveAuthSetting__mdt OneDriveSetting {
         get {
             return  [SELECT AuthEndpoint__c,AuthGrantType__c,ClientID__c,ClientSecret__c,RedirectUrl__c,Scope__c,TenantId__c,TokenUrl__c FROM OneDriveAuthSetting__mdt WITH SYSTEM_MODE];
          }
   	}
    
	public String getAccessToken() {
        if (String.isBlank(clientId) || String.isBlank(clientSecret) || String.isBlank(tokenUrl)) {
            throw new AuraHandledException('OneDrive OAuth configuration is missing.');
        }
        HttpRequest req = new HttpRequest();
        req.setEndpoint(tokenUrl);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');

        String requestBody = 'client_id=' + EncodingUtil.urlEncode(clientId, 'UTF-8') +
                            '&scope=' + EncodingUtil.urlEncode(scope, 'UTF-8') +
                            '&client_secret=' + EncodingUtil.urlEncode(clientSecret, 'UTF-8') +
                            '&grant_type=client_credentials';

        req.setBody(requestBody);
        req.setTimeout(60000);

        Http http = new Http();
        HttpResponse res = http.send(req);
        if (res.getStatusCode() == 200) {
            Map<String, Object> jsonResponse = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            if (jsonResponse.containsKey('access_token')) {
                return (String) jsonResponse.get('access_token');
            } else {
                throw new AuraHandledException('Access token not found in the response: ' + res.getBody());
            }
        } else {
            throw new AuraHandledException('Failed to retrieve access token: HTTP ' + res.getStatusCode() + ' - ' + res.getBody());
        }
    }

}