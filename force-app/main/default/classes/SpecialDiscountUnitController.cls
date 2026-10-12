public with sharing class SpecialDiscountUnitController {

    // =========================================================
    // WRAPPERS
    // =========================================================

    public class UnitWrapper {
        @AuraEnabled public Id unitId;
        @AuraEnabled public String unitName;
        @AuraEnabled public String unitCode;
        @AuraEnabled public Id blockId;
        @AuraEnabled public String blockName;
        @AuraEnabled public Id floorId;
        @AuraEnabled public String floorName;
        @AuraEnabled public Decimal floorNo;
        @AuraEnabled public String unitType;
        @AuraEnabled public String status;
    }

    public class FilterOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;

        public FilterOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    public class UnitPageResponse {
        @AuraEnabled public List<UnitWrapper> units;
        @AuraEnabled public Integer totalCount;
        @AuraEnabled public Integer pageNumber;
        @AuraEnabled public Integer pageSize;
        @AuraEnabled public Boolean hasNext;
        @AuraEnabled public Boolean hasPrevious;
    }

    public class InitialDataResponse {
        @AuraEnabled public List<FilterOption> blockOptions;
        @AuraEnabled public List<FilterOption> floorOptions;
        @AuraEnabled public List<FilterOption> unitTypeOptions;
    }


    // =========================================================
    // INITIAL FILTER DATA
    // =========================================================

    @AuraEnabled(cacheable=true)
    public static InitialDataResponse getInitialData(Id specialDiscountId) {

        if (specialDiscountId == null) {
            throw new AuraHandledException(
                'Special Discount Id is missing.'
            );
        }

        Special_Discount__c sd = [
            SELECT Id, Project__c
            FROM Special_Discount__c
            WHERE Id = :specialDiscountId
            LIMIT 1
        ];

        if (sd.Project__c == null) {
            throw new AuraHandledException(
                'Please select a Project on the Special Discount first.'
            );
        }

        Id projectId = sd.Project__c;

        InitialDataResponse response = new InitialDataResponse();

        response.blockOptions = new List<FilterOption>();
        response.floorOptions = new List<FilterOption>();
        response.unitTypeOptions = new List<FilterOption>();


        // -----------------------------------------------------
        // TOWERS / BLOCKS
        // -----------------------------------------------------

        response.blockOptions.add(
            new FilterOption('All Towers', 'ALL')
        );

        List<Block__c> blocks = [
            SELECT Id, Name
            FROM Block__c
            WHERE Project__c = :projectId
            ORDER BY Name
        ];

        Set<Id> blockIds = new Set<Id>();

        for (Block__c blockRecord : blocks) {

            blockIds.add(blockRecord.Id);

            response.blockOptions.add(
                new FilterOption(
                    blockRecord.Name,
                    String.valueOf(blockRecord.Id)
                )
            );
        }


        // -----------------------------------------------------
        // FLOORS
        // -----------------------------------------------------

        response.floorOptions.add(
            new FilterOption('All Floors', 'ALL')
        );

        if (!blockIds.isEmpty()) {

            List<Floor__c> floors = [
                SELECT
                    Id,
                    Floor_Name__c,
                    Floor_No__c,
                    Block__c,
                    Block__r.Name
                FROM Floor__c
                WHERE Block__c IN :blockIds
                ORDER BY Block__r.Name, Floor_No__c
            ];

            for (Floor__c floorRecord : floors) {

                String floorLabel = floorRecord.Floor_Name__c;

                if (floorRecord.Block__r != null) {
                    floorLabel =
                        floorRecord.Block__r.Name +
                        ' - ' +
                        floorRecord.Floor_Name__c;
                }

                response.floorOptions.add(
                    new FilterOption(
                        floorLabel,
                        String.valueOf(floorRecord.Id)
                    )
                );
            }
        }


        // -----------------------------------------------------
        // UNIT TYPES
        // Use schema describe instead of querying hundreds
        // of units just to build the filter.
        // -----------------------------------------------------

        response.unitTypeOptions.add(
            new FilterOption('All Unit Types', 'ALL')
        );

        Schema.DescribeFieldResult unitTypeDescribe =
            Unit__c.Unit_Type__c.getDescribe();

        if (unitTypeDescribe.getType() == Schema.DisplayType.PICKLIST) {

            for (Schema.PicklistEntry entry :
                unitTypeDescribe.getPicklistValues()) {

                if (entry.isActive()) {

                    response.unitTypeOptions.add(
                        new FilterOption(
                            entry.getLabel(),
                            entry.getValue()
                        )
                    );
                }
            }
        }

        return response;
    }


    // =========================================================
    // GET FLOORS FOR SELECTED TOWER
    // =========================================================

    @AuraEnabled(cacheable=true)
    public static List<FilterOption> getFloors(
        Id specialDiscountId,
        Id blockId
    ) {

        List<FilterOption> options = new List<FilterOption>();

        options.add(
            new FilterOption('All Floors', 'ALL')
        );

        if (specialDiscountId == null || blockId == null) {
            return options;
        }

        Special_Discount__c sd = [
            SELECT Project__c
            FROM Special_Discount__c
            WHERE Id = :specialDiscountId
            LIMIT 1
        ];

        Id projectId = sd.Project__c;

        List<Floor__c> floors = [
            SELECT
                Id,
                Floor_Name__c,
                Floor_No__c
            FROM Floor__c
            WHERE Block__c = :blockId
            AND Block__r.Project__c = :projectId
            ORDER BY Floor_No__c
        ];

        for (Floor__c floorRecord : floors) {

            options.add(
                new FilterOption(
                    floorRecord.Floor_Name__c,
                    String.valueOf(floorRecord.Id)
                )
            );
        }

        return options;
    }


    // =========================================================
    // PAGINATED UNIT SEARCH
    // =========================================================

    @AuraEnabled
    public static UnitPageResponse getUnits(
        Id specialDiscountId,
        Id blockId,
        Id floorId,
        String unitType,
        String searchTerm,
        Integer pageNumber,
        Integer pageSize
    ) {

        if (specialDiscountId == null) {
            throw new AuraHandledException(
                'Special Discount Id is missing.'
            );
        }


        // -----------------------------------------------------
        // PAGE VALIDATION
        // -----------------------------------------------------

        if (pageNumber == null || pageNumber < 1) {
            pageNumber = 1;
        }

        if (pageSize == null || pageSize < 1) {
            pageSize = 50;
        }

        // Hard safety limit
        if (pageSize > 100) {
            pageSize = 100;
        }


        // -----------------------------------------------------
        // GET PROJECT
        // -----------------------------------------------------

        Special_Discount__c sd = [
            SELECT Id, Project__c
            FROM Special_Discount__c
            WHERE Id = :specialDiscountId
            LIMIT 1
        ];

        if (sd.Project__c == null) {
            throw new AuraHandledException(
                'Please select a Project on the Special Discount first.'
            );
        }

        Id projectId = sd.Project__c;


        // -----------------------------------------------------
        // ALREADY SAVED UNITS
        // These will NOT appear in Available Units.
        // -----------------------------------------------------

        Set<Id> existingUnitIds = new Set<Id>();

        for (Special_Discount_Unit__c existingRecord : [
            SELECT Unit__c
            FROM Special_Discount_Unit__c
            WHERE Special_Discount__c = :specialDiscountId
            AND Unit__c != null
        ]) {
            existingUnitIds.add(existingRecord.Unit__c);
        }


        // -----------------------------------------------------
        // BUILD DYNAMIC WHERE CONDITIONS
        // -----------------------------------------------------

        List<String> conditions = new List<String>();

        conditions.add(
            'Floor__r.Block__r.Project__c = :projectId'
        );

        if (!existingUnitIds.isEmpty()) {
            conditions.add(
                'Id NOT IN :existingUnitIds'
            );
        }

        if (blockId != null) {
            conditions.add(
                'Floor__r.Block__c = :blockId'
            );
        }

        if (floorId != null) {
            conditions.add(
                'Floor__c = :floorId'
            );
        }

        if (String.isNotBlank(unitType) && unitType != 'ALL') {
            conditions.add(
                'Unit_Type__c = :unitType'
            );
        }


        String searchLike;

        if (String.isNotBlank(searchTerm)) {

            searchLike =
                '%' +
                searchTerm.trim() +
                '%';

            conditions.add(
                '(Unit_Name_Code__c LIKE :searchLike ' +
                'OR Name LIKE :searchLike)'
            );
        }


        String whereClause =
            String.join(conditions, ' AND ');


        // -----------------------------------------------------
        // COUNT
        // -----------------------------------------------------

        String countQuery =
            'SELECT COUNT() ' +
            'FROM Unit__c ' +
            'WHERE ' + whereClause;

        Integer totalCount =
            Database.countQuery(countQuery);


        // -----------------------------------------------------
        // PAGINATION
        // -----------------------------------------------------

        Integer offsetRows =
            (pageNumber - 1) * pageSize;


        // -----------------------------------------------------
        // UNIT QUERY
        // -----------------------------------------------------

        String unitQuery =
            'SELECT ' +
                'Id, ' +
                'Name, ' +
                'Unit_Name_Code__c, ' +
                'Unit_Type__c, ' +
                'Status__c, ' +
                'Floor__c, ' +
                'Floor__r.Floor_Name__c, ' +
                'Floor__r.Floor_No__c, ' +
                'Floor__r.Block__c, ' +
                'Floor__r.Block__r.Name ' +
            'FROM Unit__c ' +
            'WHERE ' + whereClause + ' ' +
            'ORDER BY ' +
                'Floor__r.Block__r.Name, ' +
                'Floor__r.Floor_No__c, ' +
                'Unit_Name_Code__c ' +
            'LIMIT :pageSize ' +
            'OFFSET :offsetRows';


        List<Unit__c> unitRecords =
            Database.query(unitQuery);


        // -----------------------------------------------------
        // MAP TO LWC WRAPPER
        // -----------------------------------------------------

        List<UnitWrapper> units =
            new List<UnitWrapper>();

        for (Unit__c unitRecord : unitRecords) {

            UnitWrapper wrapper =
                new UnitWrapper();

            wrapper.unitId =
                unitRecord.Id;

            wrapper.unitName =
                unitRecord.Name;

            wrapper.unitCode =
                unitRecord.Unit_Name_Code__c;

            wrapper.unitType =
                unitRecord.Unit_Type__c;

            wrapper.status =
                unitRecord.Status__c;


            if (unitRecord.Floor__r != null) {

                wrapper.floorId =
                    unitRecord.Floor__c;

                wrapper.floorName =
                    unitRecord.Floor__r.Floor_Name__c;

                wrapper.floorNo =
                    unitRecord.Floor__r.Floor_No__c;


                if (unitRecord.Floor__r.Block__c != null) {

                    wrapper.blockId =
                        unitRecord.Floor__r.Block__c;
                }


                if (unitRecord.Floor__r.Block__r != null) {

                    wrapper.blockName =
                        unitRecord.Floor__r.Block__r.Name;
                }
            }

            units.add(wrapper);
        }


        // -----------------------------------------------------
        // RESPONSE
        // -----------------------------------------------------

        UnitPageResponse response =
            new UnitPageResponse();

        response.units =
            units;

        response.totalCount =
            totalCount;

        response.pageNumber =
            pageNumber;

        response.pageSize =
            pageSize;

        response.hasPrevious =
            pageNumber > 1;

        response.hasNext =
            (offsetRows + units.size()) < totalCount;

        return response;
    }


    // =========================================================
    // SAVE SELECTED UNITS
    // =========================================================

    @AuraEnabled
    public static Integer saveUnits(
        Id specialDiscountId,
        List<Id> unitIds
    ) {

        if (specialDiscountId == null) {
            throw new AuraHandledException(
                'Special Discount Id is missing.'
            );
        }

        if (unitIds == null || unitIds.isEmpty()) {
            return 0;
        }


        // -----------------------------------------------------
        // GET SPECIAL DISCOUNT PROJECT
        // -----------------------------------------------------

        Special_Discount__c sd = [
            SELECT Project__c
            FROM Special_Discount__c
            WHERE Id = :specialDiscountId
            LIMIT 1
        ];

        if (sd.Project__c == null) {
            throw new AuraHandledException(
                'Special Discount does not have a Project.'
            );
        }

        Id projectId = sd.Project__c;


        // -----------------------------------------------------
        // REMOVE DUPLICATES FROM INPUT
        // -----------------------------------------------------

        Set<Id> requestedIds =
            new Set<Id>(unitIds);


        // -----------------------------------------------------
        // SECURITY / DATA VALIDATION
        //
        // Ensure selected Units actually belong to the same
        // Project as the Special Discount.
        // -----------------------------------------------------

        Set<Id> validUnitIds =
            new Set<Id>();

        for (Unit__c unitRecord : [
            SELECT Id
            FROM Unit__c
            WHERE Id IN :requestedIds
            AND Floor__r.Block__r.Project__c = :projectId
        ]) {

            validUnitIds.add(unitRecord.Id);
        }


        if (validUnitIds.isEmpty()) {

            throw new AuraHandledException(
                'No valid Units were selected.'
            );
        }


        // -----------------------------------------------------
        // FIND EXISTING JUNCTION RECORDS
        // -----------------------------------------------------

        Set<Id> existingIds =
            new Set<Id>();

        for (Special_Discount_Unit__c existingRecord : [
            SELECT Unit__c
            FROM Special_Discount_Unit__c
            WHERE Special_Discount__c = :specialDiscountId
            AND Unit__c IN :validUnitIds
        ]) {

            existingIds.add(
                existingRecord.Unit__c
            );
        }


        // -----------------------------------------------------
        // INSERT ONLY NEW RECORDS
        // -----------------------------------------------------

        List<Special_Discount_Unit__c> recordsToInsert =
            new List<Special_Discount_Unit__c>();

        for (Id unitId : validUnitIds) {

            if (!existingIds.contains(unitId)) {

                recordsToInsert.add(
                    new Special_Discount_Unit__c(
                        Special_Discount__c =
                            specialDiscountId,

                        Unit__c =
                            unitId
                    )
                );
            }
        }


        if (!recordsToInsert.isEmpty()) {
            insert recordsToInsert;
        }


        return recordsToInsert.size();
    }
}