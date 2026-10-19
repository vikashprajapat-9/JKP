@RestResource(urlMapping='/api/v1/events/register')
global without sharing class API_EventRegistration {

    @HttpPost
    global static void registerEvent() {
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');

        try {
            ResponseWrapper result = register(RestContext.request, UserInfo.getUserId());
            response.statusCode   = result.statusCode;
            response.responseBody = Blob.valueOf(JSON.serialize(result));
        } catch (Exception e) {
            System.debug('Error in API_EventRegistration.registerEvent ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_EventRegistration', 'registerEvent', e, null, 'SFA - SFDC');
            response.statusCode   = 500;
            response.responseBody = Blob.valueOf(JSON.serialize(createResponse(false, 500, 'An unexpected error occurred while registering for the event', null)));
        }
    }

    private static ResponseWrapper register(RestRequest request, String userId) {
        RequestWrapper body;
        try {
            body = (RequestWrapper) JSON.deserialize(request.requestBody.toString(), RequestWrapper.class);
        } catch (Exception e) {
            return createResponse(false, 400, 'Invalid request body', null);
        }

        if (body == null || String.isBlank(body.eventId)) {
            return createResponse(false, 400, 'eventId is required', null);
        }

        Id eventId;
        try {
            eventId = Id.valueOf(body.eventId.trim());
        } catch (Exception e) {
            return createResponse(false, 400, 'Invalid eventId', null);
        }
        if (eventId.getSObjectType() != Event__c.SObjectType) {
            return createResponse(false, 400, 'Invalid eventId', null);
        }

        List<User> users = [SELECT Id, Contact.AccountId FROM User WHERE Id = :userId WITH SYSTEM_MODE LIMIT 1];
        if (users.isEmpty()) {
            return createResponse(false, 404, 'User not found', null);
        }

        Id accountId = users[0].Contact != null ? users[0].Contact.AccountId : null;
        if (accountId == null) {
            return createResponse(false, 400, 'User is not associated with an account', null);
        }

        List<Event__c> events = [SELECT Id FROM Event__c WHERE Id = :eventId WITH SYSTEM_MODE LIMIT 1];
        if (events.isEmpty()) {
            return createResponse(false, 404, 'Event not found', null);
        }

        List<Event_Registration__c> existingRegistrations = [SELECT Id FROM Event_Registration__c WHERE Account__c = :accountId AND Event__c = :eventId WITH SYSTEM_MODE LIMIT 1];
        if (!existingRegistrations.isEmpty()) {
            return createResponse(false, 409, 'User is already registered for this event', null);
        }

        Event_Registration__c registration = new Event_Registration__c();
        registration.Account__c = accountId;
        registration.Event__c   = eventId;
        insert as system registration;

        ResponseDataWrapper data = new ResponseDataWrapper();
        data.registrationId = String.valueOf(registration.Id);
        data.eventId        = String.valueOf(eventId);
        data.accountId      = String.valueOf(accountId);

        return createResponse(true, 201, 'Event registered successfully', data);
    }

    private static ResponseWrapper createResponse(Boolean success, Integer statusCode, String message, ResponseDataWrapper data) {
        ResponseWrapper response = new ResponseWrapper();
        response.success    = success;
        response.statusCode = statusCode;
        response.message    = message;
        response.data       = data;
        return response;
    }

    public class RequestWrapper {
        public String userId;
        public String eventId;
    }

    public class ResponseWrapper {
        public Boolean success;
        public Integer statusCode;
        public String message;
        public ResponseDataWrapper data;
    }

    public class ResponseDataWrapper {
        public String registrationId;
        public String eventId;
        public String accountId;
    }
}