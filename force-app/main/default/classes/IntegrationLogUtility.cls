public class IntegrationLogUtility {
    
    public static void captureError(String className, String methodName, Exception ex, string JSONbody){
        //string JSONbody = '';
        if(Label.Integration_Log == 'True'){
        Integration_Log__c newException = createError(className, methodName, ex, JSONbody); 
        try{
            System.debug('newException-->'+newException);
            insert newException;
        }catch(Exception e){
            System.debug('error' + e.getMessage());
    }
        }
        
    }
    
    private static Integration_Log__c createError(String className, String methodName, Exception ex, String JSONbody){
        
            Integration_Log__c result 		= new Integration_Log__c();
            result.Class_Name__c 		= className;
            result.Method_Name__c 		= methodName;
            result.Error_Message__c 	= ex.getMessage();
            result.Error_Stack_Trace__c	= ex.getStackTraceString();
            result.Error_Line_No__c		= ex.getLineNumber();
            result.Error_Type__c		= ex.getTypeName();
            if (JSONbody != null) {
                result.API_JSON_body__c = JSONbody;
            }            
            return result;
        }

    public static Integration_Log__c startLog(String integrationName,String className,String methodName,String direction) {
        Integration_Log__c log = new Integration_Log__c();
        log.Integration_Name__c = integrationName;
        log.Class_Name__c = className;
        log.Method_Name__c = methodName;
        log.Integration_Direction__c = direction;
        log.Status__c = 'In Progress';
        
        insert log;
        return log;
    }

    public static void logSuccess(Integration_Log__c log,Integer statusCode,String requestBody,String responseBody) {
        log.Status__c = 'Success';
     
        log.Status_Code__c = String.valueOf(statusCode);
        log.API_CalloutRequestBody__c = requestBody;
        if(responseBody != null && responseBody.length() > 131071){
            responseBody = responseBody.substring(0,131071);
        }
        
        log.API_CalloutResponseBody__c = responseBody;
        update log;
    }

    public static void logFailure(Integration_Log__c log,Integer statusCode,Exception ex,String requestBody,String responseBody) {
        log.Status__c = 'Failed';
        
        log.Status_Code__c = String.valueOf(statusCode);
        log.API_CalloutRequestBody__c = requestBody;

        

        if(responseBody != null && responseBody.length() > 131071){
            responseBody = responseBody.substring(0,131071);
        }

        log.API_CalloutResponseBody__c = responseBody;
       
        update log;

        // Integration_Exception__c ie = new Integration_Exception__c();
        // ie.Integration_Log__c = log.Id;
        // ie.Error_Message__c = ex.getMessage();
        // ie.Stack_Trace__c = ex.getStackTraceString();
        // ie.Error_Line_No__c = ex.getLineNumber();
        // ie.Error_Type__c = ex.getTypeName();
        // insert ie;
    }

     public static Integration_Log__c buildLog(
        String integrationName,
        String className,
        String methodName,
        String direction,
        String recordId
    ) {
        Integration_Log__c log = new Integration_Log__c();
        log.Integration_Name__c = integrationName;
        log.Class_Name__c = className;
        log.Method_Name__c = methodName;
        log.Integration_Direction__c = direction;
        log.Status__c = 'In Progress';
        log.RecordId__c = recordId;
        return log;
    }

    public static void populateSuccess(Integration_Log__c log,Integer statusCode,String requestBody,String responseBody,String zcode) {
      if(statusCode == 200 || statusCode == 201){
         log.Status__c = 'Success';
        }
        log.Status_Code__c = String.valueOf(statusCode);
        if(String.isNotBlank(zcode)){
            log.Zcode__c = zcode.trim();
        }
        if(responseBody != null){
            Integer maxLength = 131071;
            log.API_CalloutResponseBody__c = responseBody.length() > maxLength ? responseBody.substring(0, maxLength) : responseBody;
        }
        
    }

    public static void populateFailure(Integration_Log__c log,Integer statusCode,String error,String responseBody,String zcode) {
        System.debug('log-->'+log);
        System.debug('statusCode-->'+statusCode);
        System.debug('error-->'+error);
        System.debug('responseBody-->'+responseBody);
        if(statusCode != 200 && statusCode != 201){
            log.Status__c = 'Failed';
        }
        else{
            log.Status__c = 'Success'; 
        }
        if(String.isNotBlank(zcode)){
                log.Zcode__c = zcode.trim();
            }
        log.Status_Code__c = String.valueOf(statusCode);
        String category = SAPErrorClassifier.classify(statusCode, responseBody);
        log.Error_Category__c = category;
        if(responseBody != null){
            Integer maxLength = 131071;
            log.API_CalloutResponseBody__c = responseBody.length() > maxLength ? responseBody.substring(0, maxLength) : responseBody;
        }

        
        String finalError = error;
        if (String.isNotBlank(responseBody)) {
            try {
            Map<String, Object> parsed =
                (Map<String, Object>) JSON.deserializeUntyped(responseBody);

            if (parsed.containsKey('error')) {
                Map<String, Object> err =
                    (Map<String, Object>) parsed.get('error');

                if (err.containsKey('message')) {
                    Map<String, Object> msg =
                        (Map<String, Object>) err.get('message');

                    finalError = String.valueOf(msg.get('value'));
                }
            }
        } catch (Exception e) {
            // Ignore parsing issues, fallback to raw error
        }
        }
        log.Error_Message__c = finalError ;
    }

}