@RestResource(urlMapping='/api/v1/faqs')
global without sharing class API_FAQ {

    @HttpGet
    global static void getFAQs() {
        RestRequest request   = RestContext.request;
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');

        try {
            FAQResponse result = getFAQData(request);
            response.statusCode   = result.statusCode;
            response.responseBody = Blob.valueOf(JSON.serialize(result));
        } catch (Exception e) {
            System.debug('Error in API_FAQ.getFAQs ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_FAQ', 'getFAQs', e, null, 'SFA - SFDC');
            response.statusCode   = 500;
            response.responseBody = Blob.valueOf(JSON.serialize(createResponse(false, 500, 'Failed to retrieve FAQs', null)));
        }
    }

    private static FAQResponse getFAQData(RestRequest request) {
        try {
            Map<String, String> requestParams = request != null && request.params != null ? request.params : new Map<String, String>();

            String status = requestParams.get('status');
            status = String.isNotBlank(status) ? status.trim() : null;
            if (String.isBlank(status)) {
                return createResponse(false, 400, 'Status parameter is required', null);
            }

            Boolean isValidStatus = false;
            for (Schema.PicklistEntry entry : FAQ__c.Type__c.getDescribe().getPicklistValues()) {
                if (entry.isActive() && entry.getValue().equalsIgnoreCase(status)) {
                    status = entry.getValue();
                    isValidStatus = true;
                    break;
                }
            }
            if (!isValidStatus) {
                return createResponse(false, 400, 'Invalid status parameter', null);
            }

            String offsetParam = requestParams.containsKey('offsetValue') ? requestParams.get('offsetValue') : requestParams.get('OffsetValue');
            String limitParam  = requestParams.containsKey('limitValue') ? requestParams.get('limitValue') : requestParams.get('LimitValue');

            Integer offsetValue = String.isNotBlank(offsetParam) && offsetParam.trim().isNumeric()? Integer.valueOf(offsetParam.trim()): 0;
            Integer limitValue = String.isNotBlank(limitParam) && limitParam.trim().isNumeric()? Integer.valueOf(limitParam.trim()): 20;

            if (offsetValue < 0 || limitValue <= 0) {
                return createResponse(false, 400, 'Invalid pagination parameters', null);
            }

            FAQData faqData = new FAQData();
            faqData.items = new List<FAQItem>();

            Integer totalCount = [SELECT COUNT() FROM FAQ__c WHERE Type__c = :status WITH SYSTEM_MODE];

            if (totalCount == 0) {
                faqData.pagination = buildPagination(0, offsetValue, limitValue, 0);
                return createResponse(true, 200, 'FAQs retrieved successfully', faqData);
            }

            List<FAQ__c> pagedFaqs = [SELECT Id, Name, Type__c, Question__c, Answer__c, CreatedDate, LastModifiedDate FROM FAQ__c WHERE Type__c = :status WITH SYSTEM_MODE ORDER BY CreatedDate ASC, Id ASC LIMIT :limitValue OFFSET :offsetValue];

            for (Integer index = 0; index < pagedFaqs.size(); index++) {
                FAQ__c faqRecord = pagedFaqs[index];

                FAQItem item = new FAQItem();
                item.id        = String.valueOf(faqRecord.Id);
                item.status    = faqRecord.Type__c;
                item.question  = faqRecord.Question__c;
                item.answer    = faqRecord.Answer__c;
                item.order     = offsetValue + index + 1;
                item.updatedAt = formatDateTime(faqRecord.LastModifiedDate);
                faqData.items.add(item);
            }

            faqData.pagination = buildPagination(totalCount, offsetValue, limitValue, pagedFaqs.size());

            return createResponse(true, 200, 'FAQs retrieved successfully', faqData);
        } catch (Exception e) {
            System.debug('Error in API_FAQ.getFAQData ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_FAQ', 'getFAQData', e, null, 'SFA - SFDC');
            return createResponse(false, 500, 'Failed to retrieve FAQs', null);
        }
    }

    private static Map<String, Object> buildPagination(Integer totalCount, Integer offsetValue, Integer limitValue, Integer returnedCount) {
        return new Map<String, Object>{
            'totalCount'  => totalCount,
            'offsetValue' => offsetValue + limitValue,
            'limitValue'  => limitValue,
            'hasMore'     => (offsetValue + returnedCount) < totalCount
        };
    }

    private static String formatDateTime(Datetime value) {
        return value == null ? null : value.format('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'', 'UTC');
    }

    private static FAQResponse createResponse(Boolean isSuccess, Integer httpStatusCode, String message, FAQData data) {
        FAQResponse apiResponse = new FAQResponse();
        apiResponse.success    = isSuccess;
        apiResponse.statusCode = httpStatusCode;
        apiResponse.message    = message;
        apiResponse.data       = data;
        return apiResponse;
    }

    public class FAQResponse {
        public Boolean success;
        public Integer statusCode;
        public String message;
        public FAQData data;
    }

    public class FAQData {
        public List<FAQItem> items;
        public Map<String, Object> pagination;
    }

    public class FAQItem {
        public String id;
        public String status;
        public String question;
        public String answer;
        public Integer order;
        public String updatedAt;
    }
}