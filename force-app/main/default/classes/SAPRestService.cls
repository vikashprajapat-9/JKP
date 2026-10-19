@RestResource(urlMapping='/api/SAP')
global with sharing class SAPRestService {

    @HttpGet
    global static void doGet() {
        String requestInfo;
        try {
            RestRequest request = RestContext.request;
            requestInfo = request == null ? null : JSON.serialize(request.params);
            String requestType = getRequestType(request);

            // switch on requestType {
            //     when 'inventory' {
            //         String recordId = request.params.get('id');
            //         String materialGroup = request.params.get('materialGroup');

            //         SAP_Inventory.GetResult result = SAP_Inventory.getMaterialMaster(recordId, materialGroup);
            //         writeResponse(result.statusCode, result.body);
            //     }
            //     when 'pricing' {
            //         SAP_Pricing.GetResult result = SAP_Pricing.getPricings(
            //             request.params.get('id'),
            //             request.params.get('materialCode'),
            //             request.params.get('materialGroup')
            //         );
            //         writeResponse(result.statusCode, result.body);
            //     }
            //     when else {
            //         throw new IllegalArgumentException('Unsupported type: ' + requestType + '.');
            //     }
            // }
        } catch (IllegalArgumentException argEx) {
            logError('doGet', argEx, requestInfo);
            writeError(400, argEx.getMessage());
        } catch (Exception ex) {
            logError('doGet', ex, requestInfo);
            writeError(500, 'Internal server error.');
        }
    }

  @HttpPost
    global static void doPost() {
        String requestBody;
        try {
            RestRequest request = RestContext.request;
            String requestType = getRequestType(request);
            requestBody = getRequestBody(request);

            switch on requestType {
                when 'inventory' {
                    SAP_Inventory.Result result = SAP_Inventory.processMaterialMasters(requestBody, SAP_Inventory.Operation.CREATE_RECORD);
                    writeResponse(result.statusCode, result.body);
                }
                when 'pricing' {
                    SAP_Pricing.Result result = SAP_Pricing.processPricings(requestBody, SAP_Pricing.Operation.CREATE_RECORD);
                    writeResponse(result.statusCode, result.body);
                }
                when 'receipts' {
                    API_Receipts.Result result = API_Receipts.processReceipts(requestBody, API_Receipts.Operation.CREATE_RECORD);
                    writeResponse(result.statusCode, result.body);
                }
                when else {
                    throw new IllegalArgumentException('Unsupported type: ' + requestType + '.');
                }
            }
        } catch (IllegalArgumentException argEx) {
            logError('doPost', argEx, requestBody);
            writeError(400, argEx.getMessage());
        } catch (Exception ex) {
            logError('doPost', ex, requestBody);
            writeError(500, 'Internal server error.');
        }
    }

    @HttpPut
    global static void doPut() {
        String requestBody;
        try {
            RestRequest request = RestContext.request;
            String requestType = getRequestType(request);
            requestBody = getRequestBody(request);

            switch on requestType {
                when 'inventory' {
                    SAP_Inventory.Result result = SAP_Inventory.processMaterialMasters(requestBody, SAP_Inventory.Operation.UPDATE_RECORD);
                    writeResponse(result.statusCode, result.body);
                }
                when 'pricing' {
                    SAP_Pricing.Result result = SAP_Pricing.processPricings(requestBody, SAP_Pricing.Operation.UPDATE_RECORD);
                    writeResponse(result.statusCode, result.body);
                }
                when 'receipts' {
                    API_Receipts.Result result = API_Receipts.processReceipts(requestBody, API_Receipts.Operation.UPDATE_RECORD);
                    writeResponse(result.statusCode, result.body);
                }
                when else {
                    throw new IllegalArgumentException('Unsupported type: ' + requestType + '.');
                }
            }
        } catch (IllegalArgumentException argEx) {
            logError('doPut', argEx, requestBody);
            writeError(400, argEx.getMessage());
        } catch (Exception ex) {
            logError('doPut', ex, requestBody);
            writeError(500, 'Internal server error.');
        }
    }


    private static String getRequestType(RestRequest request) {
        String requestType = request == null || request.params == null ? null : request.params.get('type');
        if (String.isBlank(requestType)) {
            throw new IllegalArgumentException('type query parameter is required.');
        }

        return requestType.trim().toLowerCase();
    }

    private static String getRequestBody(RestRequest request) {
        String requestBody = request.requestBody == null ? null : request.requestBody.toString();
        if (String.isBlank(requestBody)) {
            throw new IllegalArgumentException('Request body is required.');
        }

        return requestBody;
    }

    private static void writeError(Integer statusCode, String message) {
        writeResponse(statusCode, new Map<String, Object>{
            'success' => false,
            'message' => String.isBlank(message) ? 'Request failed.' : message
        });
    }

    private static void writeResponse(Integer statusCode, Object body) {
        RestResponse response = RestContext.response;
        if (response == null) {
            return;
        }

        response.statusCode = statusCode;
        response.addHeader('Content-Type', 'application/json');
        response.responseBody = Blob.valueOf(JSON.serialize(body == null ? new Map<String, Object>() : body));
    }

    private static void logError(String apexMethodName, Exception ex, String requestBody) {
        try {
            IntegrationLogUtility.captureError('SAPRestService', apexMethodName, ex, requestBody, 'SAP - SFDC');
        } catch (Exception loggingEx) {
            System.debug(LoggingLevel.ERROR, 'SAPRestService.' + apexMethodName + ' failed to write integration log: ' + loggingEx.getMessage());
        }
    }
}