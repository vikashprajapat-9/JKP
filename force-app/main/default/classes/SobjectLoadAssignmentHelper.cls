public class SobjectLoadAssignmentHelper {
    // LAKSHMI
    Public Static Map<Id, Assignment_Group__c> rv_MapOfAGIdByAG = new Map<Id, Assignment_Group__c>();
    Public Static Map<Id, List<Assignment_Group_Member__c>> rv_MapOfAGIDByASMList = new Map<Id, List<Assignment_Group_Member__c>>();
      //MAIN ASSIGNMENT METHOD
    Public static void ExecuteSobjectOwnerAssignment( List<SObject> sObjectList,  String GroupId, Id queueId ) {
        System.debug('================ ASSIGNMENT START ================');
        System.debug('GroupId ==> ' + GroupId);
        System.debug('QueueId ==> ' + queueId);
        System.debug('sObjectList ==> ' + sObjectList);

      //  Reassign_Lead__c reassignSetting =  Reassign_Lead__c.getInstance();
       // Boolean isRedistributionEnabled =   reassignSetting.Re_Distribute_Lead__c == true;
        Boolean isRedistributionEnabled = System.Label.Re_Distribute_Lead == 'true';
        System.debug( 'Re-distribution Enabled ==> ' +  isRedistributionEnabled  );
        //GET PREVIOUS OWNERS
        
        Map<Id, Set<Id>> previousOwnersByLead = new Map<Id, Set<Id>>();
        if (isRedistributionEnabled) {
            Set<Id> leadIds =  new Set<Id>();
            for (SObject objectRec : sObjectList) {
                if (objectRec.get('Id') != null) {
                    leadIds.add(   (Id)objectRec.get('Id'));
                }
            }
            if (!leadIds.isEmpty()) {
                List<Lead_Assignment_History__c> historyList = [ SELECT Id,Lead__c,Lead_Assigned_To__c
                    FROM Lead_Assignment_History__c WHERE Lead__c IN :leadIds
                    AND Lead_Assigned_To__c != null
                ];
                for ( Lead_Assignment_History__c historyRec :historyList ) {
                    if ( !previousOwnersByLead.containsKey(historyRec.Lead__c)) {
                        previousOwnersByLead.put(historyRec.Lead__c,new Set<Id>() );
                    }
                    previousOwnersByLead .get(historyRec.Lead__c) .add(historyRec.Lead_Assigned_To__c);
                }
            }
            System.debug(  'Previous Owners By Lead ==> ' + previousOwnersByLead );
        }
        
        Integer lastAllocatedId = 0;

        rv_MapOfAGIdByAG = SobjectLoadAssignmentUtility.GetassigmentGroup();
        System.debug( 'rv_MapOfAGIdByAG ==> ' + rv_MapOfAGIdByAG );
        SobjectLoadAssignment.GetAssignMentGroupMemberAndAssignmentGroup();
    
        Map<Id, List<Assignment_Group_Member__c>> assignmentGroupMembers =  SobjectLoadAssignmentUtility.assignmentGroupMembers();
        if (  assignmentGroupMembers.containsKey(GroupId) &&
            assignmentGroupMembers.get(GroupId) != null &&
            SobjectLoadAssignment.rv_MapOfAGIDByASMList.containsKey(GroupId) &&
            SobjectLoadAssignment.rv_MapOfAGIDByASMList.get(GroupId) != null
        ) {
            if ( assignmentGroupMembers.get(GroupId).size() == SobjectLoadAssignment.rv_MapOfAGIDByASMList .get(GroupId)[0].Last_Allocated_RRID__c  ) {
                lastAllocatedId = 1;
            } else {
                if (rv_MapOfAGIdByAG.containsKey(GroupId) && rv_MapOfAGIdByAG.get(GroupId) != null ) {
                    Integer lastAllocatedRRId = rv_MapOfAGIdByAG.get(GroupId).Last_Allocated_RRid__c != null ?
                        ((Integer) rv_MapOfAGIdByAG.get(GroupId).Last_Allocated_RRid__c) + 1 : 1;

                    lastAllocatedId = lastAllocatedRRId;
                    System.debug( 'Initial lastAllocatedId ==> ' + lastAllocatedId );
                } else {
                    lastAllocatedId = 1;
                }
            }
        } else {
            lastAllocatedId = 1;
        }
    
        List<Assignment_Group_Member__c> groupMembers =  SobjectLoadAssignment.rv_MapOfAGIDByASMList.get(GroupId);
        Integer totalMembers = 0;
        if (groupMembers != null) { 
            totalMembers = groupMembers.size();
        }
        System.debug(  'Total Members ==> ' +  totalMembers  );

        Map<Id, Integer> caseCounts = SobjectLoadAssignmentUtility.getCaseCount(GroupId);
        Map<Id, Integer> inDisLeadCounts = SobjectLoadAssignmentUtility.getInDiscussionLeadsCount(GroupId);

        Map<Id, Boolean> agmSLA1BreachMap = getAGMSLA1BreachStatus(GroupId);
        Map<Id, Boolean> sla2BreachMap = getAGMSLA2BreachStatus(GroupId);

        Integer totalCaseCount = 0;
        for (Integer count : caseCounts.values()) {
            totalCaseCount += count;
        }
        System.debug( 'Initial Total Case Count ==> ' +     totalCaseCount );

        Set<Integer> numbers = new Set<Integer>();

        if (SobjectLoadAssignment.rv_MapOfAGIDByASMList.get(GroupId) != null ) {
            for (Assignment_Group_Member__c agm :SobjectLoadAssignment.rv_MapOfAGIDByASMList.get(GroupId)
            ) {
                if (agm.Assignment_Id__c != null) {
                    numbers.add( (Integer)agm.Assignment_Id__c );
                }
            }
        }
        Integer lastRId =  lastAllocatedId - 1;

        if ( rv_MapOfAGIdByAG.get(GroupId) != null &&
            ((Integer)rv_MapOfAGIdByAG.get(GroupId).Max_Sobject_Assignment_Count__c ) != null
        ) {
            Integer groupMaxAssignment =   ( (Integer) rv_MapOfAGIdByAG .get(GroupId).Max_Sobject_Assignment_Count__c  );
            if (groupMaxAssignment > totalCaseCount) {
                for (SObject objectRec : sObjectList) {
                    System.debug('------------------------------------------------' );
                    System.debug( 'Processing Lead ==> ' +objectRec.get('Id') );
                    String leadStatus = '';

                    if ( objectRec.get( 'Lead_Classification__c'  ) != null  ) {
                        leadStatus = String.valueOf(objectRec.get( 'Lead_Classification__c'));
                    }
                    Boolean isHot = leadStatus == 'Hot';

                    System.debug( 'Lead Classification ==> ' + leadStatus );
                    System.debug(  'Is Hot Lead ==> ' +  isHot);

                    List<Assignment_Group_Member__c> eligibleAGMs = new List<Assignment_Group_Member__c>();

                    for (  Assignment_Group_Member__c agm : SobjectLoadAssignment.rv_MapOfAGIDByASMList .get(GroupId) ) {
                        if (caseCounts.get(agm.Id) == null) {
                            caseCounts.put(  agm.Id,  0  );
                        }
                        Integer inDiscussionCount = 0;
                        if ( inDisLeadCounts.containsKey( agm.Id ) ) {
                            inDiscussionCount = inDisLeadCounts.get( agm.Id );
                        }
                        Boolean hasHotLeadThres = (isHot &&  agm.In_Discussion_Lead_Threshold__c != null &&
                                agm.In_Discussion_Lead_Threshold__c >inDiscussionCount  )  ||  !isHot;
                        
                        // SLA1 STATUS                    
                        Boolean agmSLA1Breached = false;
                        if ( agmSLA1BreachMap.containsKey( agm.Id ) ) {
                            agmSLA1Breached =  agmSLA1BreachMap.get(agm.Id);
                        }
                          //SLA2 STATUS
                
                        Boolean sla2Breached = false;
                        if (sla2BreachMap.containsKey(agm.Id)) {
                            sla2Breached = sla2BreachMap.get(agm.Id );
                        }
                
                        Boolean slaEligible = true;
                        if (isHot && (agmSLA1Breached ||sla2Breached)) {
                            slaEligible = false;
                        }
                        //STATUS CHECK
                        Boolean basicEligible =  agm.Max_Sobject_Assignment_Count__c != null &&
                            agm.Max_Sobject_Assignment_Count__c > caseCounts.get(agm.Id)  &&
                            agm.BreakTime_Started__c == false  &&
                            !agm.Out_Of_Office__c  && agm.Active__c == true  &&  hasHotLeadThres;
                            
                            //REDISTRIBUTION CHECK
                        Boolean alreadyAssignedToThisUser =false;
                        if (isRedistributionEnabled) {
                            Id currentLeadId =   (Id)objectRec.get('Id');
                            if ( previousOwnersByLead.containsKey(  currentLeadId )
                            ) {
                                Set<Id> previousOwners =  previousOwnersByLead.get(currentLeadId);
                                if (  previousOwners != null &&  previousOwners.contains( agm.Group_Member__c ) ) {
                                    alreadyAssignedToThisUser =  true;
                                }
                            }
                            System.debug( 'REDISTRIBUTION CHECK ==> ' +  'Lead=' + currentLeadId + ', AGM=' + agm.Id + ', User=' + agm.Group_Member__c +   ', Already Assigned=' + alreadyAssignedToThisUser );
                        }

                        Boolean redistributionEligible = !isRedistributionEnabled || !alreadyAssignedToThisUser;
                        Boolean finalEligible = basicEligible &&  slaEligible && redistributionEligible;

                        System.debug('AGM ELIGIBILITY ==> ' +'AGM=' + agm.Id + ', User=' + agm.Group_Member__c +
                            ', AssignmentId=' +agm.Assignment_Id__c +', Hot=' + isHot +
                            ', SLA1Breached=' +agmSLA1Breached +', SLA2Breached=' +sla2Breached +
                            ', SLAEligible=' + slaEligible +', BasicEligible=' + basicEligible +
                            ', RedistributionEligible=' +  redistributionEligible +', FINAL=' + finalEligible  );
                        if (finalEligible) {
                            eligibleAGMs.add( agm );
                        }
                    }
                    if (eligibleAGMs.isEmpty()) {
                        System.debug( 'NO ELIGIBLE AGM ==> Lead remains in Queue. ' +  'Lead=' + objectRec.get('Id') +  ', Classification=' + leadStatus );
                        continue;
                    }
                    System.debug( 'Eligible AGM Count ==> ' + eligibleAGMs.size() );
                    
                    Assignment_Group_Member__c selectedAGM = findNextEligibleAGM( eligibleAGMs,lastAllocatedId, numbers );
                    if (selectedAGM == null) {
                        System.debug('NO ROUND ROBIN AGM FOUND ==> ' +  'Lead remains in Queue. Lead=' + objectRec.get('Id')  );
                        continue;
                    }

                     //ASSIGN LEAD
            
                    System.debug(  'SELECTED AGM ==> ' + selectedAGM.Id );
                    System.debug( 'SELECTED USER ==> ' + selectedAGM.Group_Member__c );
                    System.debug('SELECTED ASSIGNMENT ID ==> ' + selectedAGM.Assignment_Id__c   );
                    
                    if ( objectRec.get('OwnerId') != selectedAGM.Group_Member__c  ) {
                        objectRec.put( 'OwnerId',selectedAGM.Group_Member__c );
                        objectRec.put( 'Pre_Sales_Team_Member__c', selectedAGM.Group_Member__c  );
                        objectRec.put('AGM_Related_to__c', selectedAGM.Id );
                        objectRec.put( 'AG_Related_to__c', selectedAGM.Assignment_Group__c );
                        objectRec.put(  'Is_User_Assigned__c', true );
                
                        if (  objectRec.get('Status') == 'New' ||objectRec.get('Status') == null ) {
                            objectRec.put('Status','Assigned' );
                        }
                        objectRec.put( 'Lead_Assigned_Date_Time__c',  Datetime.now()  );
                        totalCaseCount++;
                        caseCounts.put(  selectedAGM.Id, caseCounts.get( selectedAGM.Id ) + 1  );
                        lastRId =(Integer)selectedAGM.Assignment_Id__c;
                        lastAllocatedId = getNextAssignmentId(  Integer.valueOf(String.valueOf(selectedAGM.Assignment_Id__c)), numbers );

                        System.debug( 'LEAD ASSIGNED SUCCESSFULLY ==> ' + 'Lead=' + objectRec.get('Id') +
                            ', User=' + selectedAGM.Group_Member__c +', AGM=' +selectedAGM.Id + ', Next RR=' +  lastAllocatedId);
                    }
                }
                //UPDATE ASSIGNMENT GROUP
                
                if (!sObjectList.isEmpty()) {
                    Assignment_Group__c ov_AGTobeUpdated = new Assignment_Group__c();
                    ov_AGTobeUpdated.Id = rv_MapOfAGIdByAG .get(GroupId) .Id;

                    if (lastRId > 0) {
                        ov_AGTobeUpdated.Last_Allocated_RRid__c = lastRId;
                        Database.SaveResult agUpdateResult =  Database.update(  ov_AGTobeUpdated, false  );
                        if (!agUpdateResult.isSuccess()) {
                            for (Database.Error err :  agUpdateResult.getErrors() ) {
                                System.debug( 'Assignment Group update failed: ' + err.getMessage() );
                            }
                        }

                    }
                      //UPDATE LEADS
                    Database.SaveResult[] sObjectUpdateResults = Database.update( sObjectList,  false  );
                    for (  Database.SaveResult result :  sObjectUpdateResults ) {
                        if (!result.isSuccess()) {
                            for ( Database.Error err : result.getErrors() ) {
                                System.debug( 'SObject update failed: ' +  err.getMessage() );
                            }
                        }
                    }
                }

            } else {
                System.debug( 'ASSIGNMENT GROUP MAX CAPACITY REACHED ==> ' + 'Max=' + groupMaxAssignment +', Current=' + totalCaseCount  );
            }
        }
        System.debug(  '================ ASSIGNMENT END ================'  );
    }
    
     //FIND NEXT ELIGIBLE AGM
    private static Assignment_Group_Member__c findNextEligibleAGM( List<Assignment_Group_Member__c> eligibleAGMs, Integer startingRRId,  Set<Integer> allAssignmentIds   ) {

        if ( eligibleAGMs == null || eligibleAGMs.isEmpty()  ) {
            return null;
        }
        for (  Assignment_Group_Member__c agm : eligibleAGMs  ) {

            if ( agm.Assignment_Id__c != null && agm.Assignment_Id__c == startingRRId ) {
                return agm;
            }
        }
    
        List<Integer> sortedEligibleIds = new List<Integer>();
        for ( Assignment_Group_Member__c agm :  eligibleAGMs  ) {
            if (agm.Assignment_Id__c != null) {
                sortedEligibleIds.add( (Integer)agm.Assignment_Id__c   );
            }
        }
        sortedEligibleIds.sort();
    
        for (Integer eligibleId : sortedEligibleIds  ) {
            if (eligibleId > startingRRId) {
                for ( Assignment_Group_Member__c agm :  eligibleAGMs ) {
                    if (agm.Assignment_Id__c ==  eligibleId) {
                        return agm;
                    }
                }
            }
        }
        for ( Integer eligibleId : sortedEligibleIds ) {
            for (Assignment_Group_Member__c agm : eligibleAGMs  ) {
                if (agm.Assignment_Id__c == eligibleId   ) {
                    return agm;
                }
            }
        }
        return null;
    }
     //GET NEXT ROUND ROBIN ID
    private static Integer getNextAssignmentId(Integer currentAssignmentId,Set<Integer> assignmentIds ) {
        if (assignmentIds == null ||  assignmentIds.isEmpty()   ) {

            return 1;
        }
        List<Integer> sortedIds =new List<Integer>(  assignmentIds  );
        sortedIds.sort();
        for ( Integer assignmentId : sortedIds ) {
            if ( assignmentId > currentAssignmentId  ) {
                return assignmentId;
            }
        }
        return sortedIds[0];
    }

    private static Map<Id, Boolean> getAGMSLA1BreachStatus(String GroupId ) {
        Map<Id, Boolean> agmSLA1BreachMap = new Map<Id, Boolean>();
        List<Assignment_Group_Member__c> agmList = SobjectLoadAssignment.rv_MapOfAGIDByASMList.get(GroupId);
        if (  agmList == null || agmList.isEmpty() ) {
            return agmSLA1BreachMap;
        }
        /*
         * Map User ID -> AGM
         */
        Map<Id, Assignment_Group_Member__c> agmByUserId = new Map<Id, Assignment_Group_Member__c>();
        Set<Id> userIds =  new Set<Id>();

        for ( Assignment_Group_Member__c agm :agmList ) {
            if (agm.Group_Member__c != null ) {
                userIds.add(agm.Group_Member__c );
                agmByUserId.put(agm.Group_Member__c,  agm );
            }
        }
       //Default SLA1 period = 1 month
        Integer periodMonths = 1;
        for (   Assignment_Group_Member__c agm :  agmList ) {
            if (  agm.SLA1_Period__c != null  ) {
                periodMonths =Integer.valueOf( String.valueOf(agm.SLA1_Period__c)  );
                break;
            }
        }
        Date periodStartDate =  Date.today().addMonths(-periodMonths);
        Datetime periodStartDateTime = Datetime.newInstance(periodStartDate,Time.newInstance(0,0,0, 0) );
        
        List<Lead_Assignment_History__c> historyList = [ SELECT Id,Lead__c, Lead_Assigned_To__c,
                SLA1__c, CreatedDate FROM Lead_Assignment_History__c
            WHERE Lead_Assigned_To__c IN :userIds AND CreatedDate >= :periodStartDateTime   ];

        Map<Id, Integer> totalAssignedByAGM = new Map<Id, Integer>();
        Map<Id, Integer> sla1BreachedByAGM =new Map<Id, Integer>();

        for ( Lead_Assignment_History__c historyRec : historyList ) {
            if ( historyRec.Lead_Assigned_To__c == null ||!agmByUserId.containsKey( historyRec.Lead_Assigned_To__c  )) {
                continue;
            }
            Id agmId = agmByUserId.get(historyRec.Lead_Assigned_To__c).Id;
            Integer totalCount =totalAssignedByAGM.containsKey(agmId) ? totalAssignedByAGM.get( agmId): 0;
            totalAssignedByAGM.put( agmId, totalCount + 1 );
            if ( historyRec.SLA1__c == true ) {
                Integer breachCount = sla1BreachedByAGM.containsKey( agmId )  ? sla1BreachedByAGM.get(agmId) : 0;
                sla1BreachedByAGM.put( agmId,breachCount + 1 );
            }
        }

        for ( Assignment_Group_Member__c agm : agmList ) {
            Integer totalAssigned = totalAssignedByAGM.containsKey(agm.Id ) ? totalAssignedByAGM.get(agm.Id)  :  0;
            Integer breached = sla1BreachedByAGM.containsKey( agm.Id  )? sla1BreachedByAGM.get(agm.Id)  : 0;
            Boolean sla1Breached = false;
            if (totalAssigned > 0) {
                Decimal thresholdPercentage = agm.SLA1_Threshold_Percentage__c != null ?  agm.SLA1_Threshold_Percentage__c : 10;
                Decimal breachPercentage = (Decimal.valueOf(breached) / Decimal.valueOf(totalAssigned))* 100;
                sla1Breached =  breachPercentage >= thresholdPercentage;

                System.debug( '========== SLA1 DETAILS ==========' );
                System.debug( 'AGM = ' +agm.Id);
                System.debug( 'Total Assigned = ' +  totalAssigned);
                System.debug( 'SLA1 Breached Leads = ' +  breached );
                System.debug(  'SLA1 Breach % = ' + breachPercentage  );
                System.debug( 'SLA1 Threshold % = ' + thresholdPercentage  );
                System.debug('SLA1 AGM Breached = ' + sla1Breached  );
                System.debug(  '===================================' );
            }
            agmSLA1BreachMap.put(  agm.Id, sla1Breached);
        }
        return agmSLA1BreachMap;
    }

    private static Map<Id, Boolean> getAGMSLA2BreachStatus( String GroupId) {
        Map<Id, Boolean> sla2BreachMap = new Map<Id, Boolean>();
        List<Assignment_Group_Member__c> agmList = SobjectLoadAssignment.rv_MapOfAGIDByASMList.get(GroupId);

        if ( agmList == null || agmList.isEmpty()  ) {
            return sla2BreachMap;
        }

         //Map User ID -> AGM
    
        Map<Id, Assignment_Group_Member__c> agmByUserId = new Map<Id, Assignment_Group_Member__c>();

        Set<Id> userIds = new Set<Id>();
        for (Assignment_Group_Member__c agm :agmList  ) {
            if ( agm.Group_Member__c != null  ) {
                userIds.add( agm.Group_Member__c );
                agmByUserId.put(agm.Group_Member__c, agm  );
            }
        }
       //SLA2 period = 2 months
    
        Integer sla2PeriodMonths = 2;
        for ( Assignment_Group_Member__c agm : agmList ) {
            if (  agm.SLA2_Period__c != null ) {
                sla2PeriodMonths = Integer.valueOf( String.valueOf(   agm.SLA2_Period__c   )   );
                break;
            }
        }
        Date periodStartDate = Date.today().addMonths(-sla2PeriodMonths  );
        Datetime periodStartDateTime = Datetime.newInstance( periodStartDate,Time.newInstance( 0,  0, 0,0  ) );
    
        List<Lead_Assignment_History__c> historyList = [ SELECT Id,  Lead__c,
                Lead_Assigned_To__c,SLA2__c,  CreatedDate
            FROM Lead_Assignment_History__c
            WHERE Lead_Assigned_To__c IN :userIds
            AND CreatedDate >= :periodStartDateTime
        ];

        Map<Id, Integer> totalAssignedByAGM = new Map<Id, Integer>();
        Map<Id, Integer> sla2BreachedByAGM = new Map<Id, Integer>();

        for ( Lead_Assignment_History__c historyRec : historyList   ) {
            if ( historyRec.Lead_Assigned_To__c == null  ) {
                continue;
            }
            if ( !agmByUserId.containsKey( historyRec.Lead_Assigned_To__c)  ) {
                continue;
            }
            Id agmId = agmByUserId.get(  historyRec.Lead_Assigned_To__c   )  .Id;
            Integer totalCount = totalAssignedByAGM.containsKey( agmId) ? totalAssignedByAGM.get( agmId   )  :  0;
            totalAssignedByAGM.put(  agmId, totalCount + 1  );
            if ( historyRec.SLA2__c == true  ) {
                Integer breachCount = sla2BreachedByAGM.containsKey(  agmId ) ? sla2BreachedByAGM.get( agmId) :  0;
                sla2BreachedByAGM.put( agmId, breachCount + 1 );
            }
        }
        //Calculate breach percentage
        
        for ( Assignment_Group_Member__c agm : agmList   ) {
            Integer totalAssigned = totalAssignedByAGM.containsKey(  agm.Id  ) ? totalAssignedByAGM.get( agm.Id  )  :  0;
            Integer breached = sla2BreachedByAGM.containsKey( agm.Id   )  ? sla2BreachedByAGM.get( agm.Id ) : 0;
            Boolean sla2Breached = false;

            if (totalAssigned > 0) {
                Decimal thresholdPercentage = agm.SLA2_Threshold_Percentage__c != null ? agm.SLA2_Threshold_Percentage__c: 10;
                Decimal breachPercentage = (Decimal.valueOf( breached ) / Decimal.valueOf(totalAssigned) ) * 100;

                sla2Breached = breachPercentage >= thresholdPercentage;

                System.debug('========== SLA2 DETAILS =========='  );
                System.debug(  'AGM = ' +  agm.Id  );
                System.debug( 'SLA2 Period Months = ' + sla2PeriodMonths );
                System.debug( 'Period Start = ' + periodStartDateTime  );
                System.debug( 'Total Assigned = ' +  totalAssigned  );
                System.debug( 'SLA2 Breached Leads = ' + breached );
                System.debug( 'SLA2 Breach % = ' + breachPercentage);
                System.debug( 'SLA2 Threshold % = ' + thresholdPercentage );
                System.debug('SLA2 AGM Breached = ' + sla2Breached );
                System.debug( '===================================' );
            }

            sla2BreachMap.put(agm.Id,sla2Breached);
        }
        return sla2BreachMap;
    }
}