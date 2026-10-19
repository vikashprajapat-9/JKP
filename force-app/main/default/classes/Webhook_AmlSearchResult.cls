@RestResource(urlMapping='/api/v2/aml-search-result')
global with sharing class Webhook_AmlSearchResult {

    private static final String CLASS_NAME = 'Webhook_AmlSearchResult';
    private static final String INTEGRATION_NAME = 'Webhook Aml';
    private static final String DIRECTION = 'AML - SFDC';
    private static final String METHOD_NAME = 'AmlSearchResult';

    @HttpPost
    global static void AmlSearchResult() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        String requestBody;
        String responseBody;
        Integration_Log__c logRecord;
        Integer statusCode = 200;
        try {
            requestBody = req.requestBody == null? null: req.requestBody.toString();
            System.debug(LoggingLevel.INFO, 'Solytics AML webhook received.');
            String recordId = null;
            if (String.isNotBlank(requestBody)) {
                Map<String, Object> payload =(Map<String, Object>) JSON.deserializeUntyped(requestBody);
                if (payload.containsKey('sfdc_lead_id')) {
                    recordId = String.valueOf(payload.get('sfdc_lead_id'));
                }
            }
            logRecord = IntegrationLogUtility.buildLog(INTEGRATION_NAME,CLASS_NAME,METHOD_NAME,DIRECTION,recordId);
            logRecord.API_JSON_body__c = requestBody;
            logRecord.API_CalloutRequestBody__c = truncateText(requestBody);


            responseBody = '{"success":true,"message":"Webhook received"}';
            statusCode = 200;

            IntegrationLogUtility.populateSuccess(logRecord,  statusCode,  requestBody,  responseBody);
            saveLogSafely(logRecord);
            res.statusCode = statusCode;
            res.addHeader('Content-Type', 'application/json');
            res.responseBody = Blob.valueOf(responseBody);
        } catch (Exception e) {
            statusCode = 500;
            responseBody = '{"success":false,"message":"Webhook processing failed"}';
            System.debug(LoggingLevel.ERROR,'AML webhook error: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR,'AML webhook stack trace: ' + e.getStackTraceString());
            try {
                if (logRecord == null) {
                    logRecord = IntegrationLogUtility.buildLog(INTEGRATION_NAME,CLASS_NAME,METHOD_NAME,DIRECTION, null);
                }

                logRecord.Status__c = 'Failed';
                logRecord.Status_Code__c = String.valueOf(statusCode);
                logRecord.API_JSON_body__c = truncateText(requestBody);
                logRecord.API_CalloutRequestBody__c =truncateText(requestBody);
                logRecord.API_CalloutResponseBody__c = truncateText(responseBody);
                logRecord.Error_Message__c = e.getMessage();
                logRecord.Error_Stack_Trace__c =e.getStackTraceString();
                logRecord.Error_Line_No__c = e.getLineNumber();
                logRecord.Error_Type__c = e.getTypeName();
                saveLogSafely(logRecord);

            } catch (Exception loggingException) {
                System.debug(LoggingLevel.ERROR, 'Unable to create AML failure log: ' + loggingException.getMessage());
            }

            res.statusCode = statusCode;
            res.addHeader('Content-Type', 'application/json');
            res.responseBody = Blob.valueOf(responseBody);
        }
    }

    private static void saveLogSafely(Integration_Log__c logRecord) {
        try {
            System.debug(LoggingLevel.INFO, 'Saving AML Integration Log. Record: ' +JSON.serialize(logRecord));
            Database.SaveResult result;
            if (logRecord.Id == null) {
                result = Database.insert(logRecord,  AccessLevel.SYSTEM_MODE);
            } else {
                Database.SaveResult[] results = Database.update(new List<Integration_Log__c>{ logRecord }, false);
                if (!results.isEmpty()) {
                    result = results[0];
                }
            }
            if (result != null && result.isSuccess()) {
                System.debug(LoggingLevel.INFO,'AML Integration Log saved successfully. ID: ' + result.getId());
            } else if (result != null) {
                for (Database.Error err : result.getErrors()) {
                    System.debug(LoggingLevel.ERROR, 'AML Integration Log DML failure: ' +err.getStatusCode() + ' - ' +  err.getMessage());
                    System.debug(LoggingLevel.ERROR,'Fields causing error: ' + err.getFields());
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Unexpected error saving AML Integration Log: ' + e.getMessage());

            System.debug(LoggingLevel.ERROR,'Stack trace: ' + e.getStackTraceString());
        }
    }
    private static String truncateText(String value) {
        if (value == null) {
            return null;
        }
        Integer maxLength = 131071;
        return value.length() > maxLength ? value.substring(0, maxLength) : value;
    }
}