@RestResource(urlMapping='/api/v2/aml-search-result')
global with sharing class Webhook_AmlSearchResult {

    @HttpPost
    global static void AmlSearchResult() {
        RestRequest request = RestContext.request;
        RestResponse response = RestContext.response;
        try {
            if (request.requestBody == null) {
                response.statusCode = 400;
                response.responseBody = Blob.valueOf('{"error":"Request body is required"}');
                return;
            }

            String body = request.requestBody.toString();
            System.debug('AML webhook received');
            Map<String, Object> payload =(Map<String, Object>) JSON.deserializeUntyped(body);
            String feature = (String) payload.get('feature');
            if (String.isBlank(feature)) {
                response.statusCode = 400;
                response.responseBody = Blob.valueOf('{"error":"Feature is required"}');
                return;
            }
            System.debug('Feature: ' + feature);
            response.statusCode = 200;
            response.responseBody = Blob.valueOf('{"message":"AML webhook received successfully"}');

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,'AML webhook processing failed: ' + e.getMessage() );
            response.statusCode = 400;
            response.responseBody = Blob.valueOf('{"error":"Invalid request payload"}');
        }
    }
}