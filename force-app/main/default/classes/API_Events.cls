@RestResource(urlMapping='/api/v1/events/*')
global without sharing class API_Events {

    private static final Integer DEFAULT_OFFSET = 0;
    private static final Integer DEFAULT_LIMIT  = 10;
    private static final Integer MAX_LIMIT      = 100;

    @HttpGet
    global static void getEvents() {
        RestRequest request   = RestContext.request;
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');

        try {
            EventsResponse result = buildEventsResponse(request);
            response.statusCode   = result.statusCode;
            response.responseBody = Blob.valueOf(JSON.serialize(result));
        } catch (Exception e) {
            System.debug('Error in API_Events.getEvents ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_Events', 'getEvents', e, null, 'SFA - SFDC');
            response.statusCode   = 500;
            response.responseBody = Blob.valueOf(JSON.serialize(createResponse(false, 500, 'An unexpected error occurred while retrieving events', null)));
        }
    }

    private static EventsResponse buildEventsResponse(RestRequest request) {
        try {
            Map<String, String> params = request != null && request.params != null ? request.params : new Map<String, String>();

            String userId = UserInfo.getUserId();
            if (String.isBlank(userId)) {
                return createResponse(false, 400, 'userId is required', null);
            }
            userId = userId.trim();
            if (!isValidSalesforceId(userId)) {
                return createResponse(false, 400, 'Invalid userId', null);
            }

            Integer offsetValue = parseInteger(params.get('offsetValue'), DEFAULT_OFFSET);
            Integer limitValue  = parseInteger(params.get('limitValue'), DEFAULT_LIMIT);
            if (offsetValue == null || offsetValue < 0 || limitValue == null || limitValue <= 0) {
                return createResponse(false, 400, 'Invalid pagination parameters', null);
            }
            limitValue = Math.min(limitValue, MAX_LIMIT);

            List<User> matchedUsers = [SELECT Id, ContactId, Contact.AccountId FROM User WHERE Id = :userId WITH SYSTEM_MODE LIMIT 1];
            if (matchedUsers.isEmpty()) {
                return createResponse(false, 404, 'User not found', null);
            }
            Id accountId = matchedUsers[0].Contact != null ? matchedUsers[0].Contact.AccountId : null;
            if (accountId == null) {
                return createResponse(false, 400, 'User is not associated with an account', null);
            }

            Datetime currentDateTime = System.now();

            Integer totalCount = [SELECT COUNT() FROM Event__c WHERE Start_Date_Time__c > :currentDateTime WITH SYSTEM_MODE];

            EventsData data = new EventsData();
            data.events = new List<EventWrapper>();

            if (totalCount == 0) {
                data.pagination = buildPagination(0, offsetValue, limitValue, 0);
                return createResponse(true, 200, 'Events retrieved successfully', data);
            }

            List<Event__c> pagedEvents = [SELECT Id, Name, Description__c, Start_Date_Time__c, End_Date_Time__c,Venue__Street__s, Venue__City__s, Venue__StateCode__s,Venue__PostalCode__s, Venue__CountryCode__s FROM Event__c WHERE Start_Date_Time__c > :currentDateTime WITH SYSTEM_MODE ORDER BY Start_Date_Time__c ASC, Id ASC LIMIT :limitValue OFFSET :offsetValue];

            Set<Id> eventIds = new Map<Id, Event__c>(pagedEvents).keySet();

            Set<Id> registeredEventIds = new Set<Id>();
            for (Event_Registration__c registration : [SELECT Id, Event__c FROM Event_Registration__c WHERE Event__c IN :eventIds AND Account__c = :accountId WITH SYSTEM_MODE]) {
                registeredEventIds.add(registration.Event__c);
            }

            Map<Id, String> imageUrlByEventId = getEventImageUrls(eventIds);

            for (Event__c eventRecord : pagedEvents) {
                EventWrapper item = new EventWrapper();
                item.eventId          = String.valueOf(eventRecord.Id);
                item.title            = eventRecord.Name;
                item.description      = eventRecord.Description__c;
                item.imageUrl         = imageUrlByEventId.get(eventRecord.Id);
                item.startDateTime    = formatIso8601(eventRecord.Start_Date_Time__c);
                item.endDateTime      = formatIso8601(eventRecord.End_Date_Time__c);
                item.formattedDate    = formatDisplayDate(eventRecord.Start_Date_Time__c);
                item.formattedTime    = formatDisplayTime(eventRecord.Start_Date_Time__c, eventRecord.End_Date_Time__c);
                item.venue            = buildVenueAddress(eventRecord);
                item.isRegistered     = registeredEventIds.contains(eventRecord.Id);
                item.registrationOpen = eventRecord.Start_Date_Time__c > currentDateTime;
                data.events.add(item);
            }

            data.pagination = buildPagination(totalCount, offsetValue, limitValue, pagedEvents.size());

            return createResponse(true, 200, 'Events retrieved successfully', data);
        } catch (Exception e) {
            System.debug('Error in API_Events.buildEventsResponse ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_Events', 'buildEventsResponse', e, null, 'SFA - SFDC');
            return createResponse(false, 500, 'An unexpected error occurred while retrieving events', null);
        }
    }

    private static Map<Id, String> getEventImageUrls(Set<Id> eventIds) {
        Map<Id, String> imageUrlByEventId = new Map<Id, String>();
        if (eventIds.isEmpty()) {
            return imageUrlByEventId;
        }

        for (Sub_Document__c subDocument : [SELECT Id, Event__c, File_Url__c FROM Sub_Document__c WHERE Event__c IN :eventIds AND File_Url__c != null WITH SYSTEM_MODE ORDER BY CreatedDate ASC, Id ASC]) {
            if (!imageUrlByEventId.containsKey(subDocument.Event__c)) {
                imageUrlByEventId.put(subDocument.Event__c, subDocument.File_Url__c);
            }
        }
        return imageUrlByEventId;
    }

    private static String buildVenueAddress(Event__c eventRecord) {
        List<String> addressParts = new List<String>{
            eventRecord.Venue__Street__s,
            eventRecord.Venue__City__s,
            eventRecord.Venue__StateCode__s,
            eventRecord.Venue__PostalCode__s,
            eventRecord.Venue__CountryCode__s
        };
        List<String> nonBlankParts = new List<String>();
        for (String part : addressParts) {
            if (String.isNotBlank(part)) {
                nonBlankParts.add(part);
            }
        }
        return nonBlankParts.isEmpty() ? null : String.join(nonBlankParts, ', ');
    }

    private static String formatIso8601(Datetime value) {
        return value == null ? null : value.format('yyyy-MM-dd\'T\'HH:mm:ssXXX');
    }

    private static String formatDisplayDate(Datetime value) {
        return value == null ? null : value.format('MMM d, yyyy');
    }

    private static String formatDisplayTime(Datetime startValue, Datetime endValue) {
        if (startValue == null) {
            return null;
        }
        String startTime = startValue.format('h:mm a');
        if (endValue == null) {
            return startTime;
        }
        return startTime + ' - ' + endValue.format('h:mm a');
    }

    private static Map<String, Object> buildPagination(Integer totalCount, Integer offsetValue, Integer limitValue, Integer returnedCount) {
        return new Map<String, Object>{
            'hasMore'     => (offsetValue + returnedCount) < totalCount,
            'limitValue'  => limitValue,
            'offsetValue' => offsetValue + limitValue,
            'totalCount'  => totalCount
        };
    }

    private static Integer parseInteger(String rawValue, Integer defaultValue) {
        if (String.isBlank(rawValue)) {
            return defaultValue;
        }
        String trimmed = rawValue.trim();
        return trimmed.isNumeric() ? Integer.valueOf(trimmed) : null;
    }

    private static Boolean isValidSalesforceId(String recordId) {
        try {
            Id.valueOf(recordId);
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    private static EventsResponse createResponse(Boolean isSuccess, Integer httpStatusCode, String message, EventsData data) {
        EventsResponse apiResponse = new EventsResponse();
        apiResponse.success    = isSuccess;
        apiResponse.statusCode = httpStatusCode;
        apiResponse.message    = message;
        apiResponse.data       = data;
        return apiResponse;
    }

    public class EventsResponse {
        public Boolean success;
        public Integer statusCode;
        public String message;
        public EventsData data;
    }

    public class EventsData {
        public List<EventWrapper> events;
        public Map<String, Object> pagination;
    }

    public class EventWrapper {
        public String eventId;
        public String title;
        public String description;
        public String imageUrl;
        public String startDateTime;
        public String endDateTime;
        public String formattedDate;
        public String formattedTime;
        public String venue;
        public Boolean isRegistered;
        public Boolean registrationOpen;
    }
}