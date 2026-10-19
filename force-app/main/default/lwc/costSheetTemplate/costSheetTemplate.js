import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getCompanyDetails from '@salesforce/apex/costSheetTemplateController.getCompanyDetails';
import fetchProjectAndPicklistDetails from '@salesforce/apex/costSheetTemplateController.fetchProjectAndPicklistDetails';
import getTowerFloorUnitPricingElementData from '@salesforce/apex/costSheetTemplateController.getTowerFloorUnitPricingElementData';
import fetchPricingBasedonSearch from '@salesforce/apex/costSheetTemplateController.fetchPricingBasedonSearch';
import saveAllRecords from '@salesforce/apex/costSheetTemplateController.saveAllRecords';
import fetchExistingData from '@salesforce/apex/costSheetTemplateController.fetchExistingData';
import checkIfTemplateCodeExists from '@salesforce/apex/costSheetTemplateController.checkIfTemplateCodeExists';
// import saveRecordsBasedOnExistingData from '@salesforce/apex/costSheetTemplateController.saveRecordsBasedOnExistingData';

export default class CostSheetTemplate extends LightningElement {
    @api recordId;
    @track columns = [
        {label: 'Block', fieldName: 'Block', type: 'text'},
        {label: 'Floor',fieldName: 'Floor',type: 'text'},
        {label: 'Unit',fieldName: 'Name',type: 'text'}
    ];
    sticky = false;
    timeout = 2000;
    @track showErrorTop;
    @track editRecord = false;
    @track lockRecord = false;
    @track companyOptions = [];
    @track projectOptions = [];
    @track pricingElementList = [];
    @track originalCostPricingAssociationsList = [];
    @track selectedPricingElementList = [];
    @track towerOptions = [];
    @track floorOptions = [];
    @track isDisabled1 = false;
    @track showAccordians = false;
    @track showProjectUnitAllocation = false;
    @track showPricingElement = false;
    @track showPricingLowerDiv = false;
    @track displayUnitRecords = false;
    @track firstNext = false;
    @track secondNext = false;
    @track selectedTower = '';
    @track selectedFloor = '';
    @track BlockList = [];
    @track floorList = [];
    @track unitList = [];
    @track taxMasterList = [];
    @track unitListformatted = [];
    @track newunitListformatted = [];
    @track taxListformatted = [];
    @track selectedUnitsToDisplay = [];
    @track costSheetTemObj = {
        Company__c : '',
        Project__c : '',
        Template_Code__c : '',
        Active__c : true,
        Name : '',
        Id : ''
    }

    sections = [
        { Id : 1, Name : 'Pricing Elements'},
        { Id : 2, Name : 'Project Unit Allocation'}
    ]

    connectedCallback(){
        debugger;
        setTimeout(() => {
            console.log('recordId ===> ' + this.recordId);
            this.editRecord = (this.recordId != null && this.recordId != '') ? true : false;
            if(this.editRecord == true){
                this.fetchExistingRecordDetails();
            }
            this.getCompanyList();
        }, 100);
    }

    @track projectName = '';
    objByField = {
        PE_Type__c: 'Cost_Pricing_Association__c',
        Type__c: 'Cost_Pricing_Association__c',
        Unit__c: 'Cost_Pricing_Association__c',
        Tax_Type__c: 'Tax_Master__c'
    };

    @track recordsToDisplay = [];
    jobPaginationCallback(event) {
        debugger;
        this.recordsToDisplay = event.detail.recordToDisplay.map(item => ({
            ...item,
            isChecked : this.selectedPricingElementList.includes(item.Id)
        }));
        // console.log('Paginated data ===> ' + JSON.stringify(this.recordsToDisplay));
    }

    jobPaginationCallbackAsstn(event){
        debugger;
        this.costPricingAssociationsList = event.detail.recordToDisplay;
    }

    @track selectedUnitsToDisplayPaginated = [];
    jobPaginationSelectedUnits(event){
        debugger;
        this.selectedUnitsToDisplayPaginated = event.detail.recordToDisplay;
    }

    handleSave(){
        debugger;
        let isEmptySequence = this.costPricingAssociationsList.some(item => !item.Sequence__c || item.Sequence__c === '');
        if (isEmptySequence) {
            this.showToast('Error', 'Sequence field cannot be empty for any Pricing Element.', 'error');
            return;
        }
        
        let typeWiseMap = new Map(); 
        let hasDuplicates = false;

        this.costPricingAssociationsList.forEach(item => {
            let type = item.Type__c || 'Undefined';
            let sequence = item.Sequence__c;

            if (!typeWiseMap.has(type)) {
                typeWiseMap.set(type, []);
            }

            let seqList = typeWiseMap.get(type);
            if (seqList.includes(sequence)) {
                hasDuplicates = true;
            } else {
                seqList.push(sequence);
                typeWiseMap.set(type, seqList);
            }
        });
        
        if (hasDuplicates) {
            this.showToast('Error', 'Duplicate Sequence found in same Type group (Agreement or Amenities).', 'error');
            return;
        }

        if(this.recordId == null || this.recordId == ''){
            this.validateCode();
        }
        const costSheetTempId = (this.recordId != null && this.recordId != '') ? this.recordId : null;
        // var selectedUnitIds = this.newSelectedList.map(item => item.Id);
        var selectedUnitIds = this.selectedUnitsList;

        // Code to make atleast one tax element mandatory for each pricing association
        // const hasEmptyTaxList = this.costPricingAssociationsList.some(pricing => pricing.taxList.some(tax => !tax.Name));
        // if(hasEmptyTaxList){
        //     this.showToast('Error', 'Atleast one tax has to be added to each Pricing Element!!!', 'error');
        //     return;
        // }
        const costPricingAssociationsListJson = JSON.stringify(this.costPricingAssociationsList);
        console.log('costPricingAssociationsList ===> ' + JSON.stringify(this.costPricingAssociationsList));
        
        saveAllRecords({ costSheetTempId : costSheetTempId, costSheetTempRec : this.costSheetTemObj, selectedUnitIds : selectedUnitIds, costPricingAssociationsListJson : costPricingAssociationsListJson })
        .then(result => {
            if(result.startsWith('Error')){
                this.showErrorTop = false;
                this.showToast('Error', 'Error Processing the Record !!!', 'error');
            }else{
                this.isDisabled1 = true;
                this.showErrorTop = false;
                const recordId = result;
                this.showToast('Success', 'Record Created Successfully!!!', 'success');
                window.top.location.href = `/lightning/r/Cost_Sheet_Template__c/${recordId}/view`;
            }
        })
        .catch(error => {
            console.log('error ===> ' + error);
        });
    }

    fetchExistingRecordDetails(){
        debugger;
        fetchExistingData({ costSheetTempId : this.recordId, ObjectByField : this.objByField})
        .then(result => {
            if(result){
                this.lockRecord = result.lockRecord == true ? true : false;
                this.costSheetTemObj = result.costSheetTemObj;
                let selectedUnits = [];
                if(Array.isArray(result.costSheetTemObj.Cost_Unit_Linking__r)){
                    selectedUnits = result.costSheetTemObj.Cost_Unit_Linking__r.map(unit => unit.Unit__c);
                }
                this.selectedUnitsList = selectedUnits;
                console.log('selectedUnits ===> ' + JSON.stringify(this.selectedUnitsList));

                var newSelectedList = result.costSheetTemObj.Cost_Unit_Linking__r.map(unit => {
                    return {
                        Id: unit.Unit__c,
                        Name: unit.Unit__r.Name,
                        Block: unit.Unit__r.Floor__r.Block__c,
                        Floor: unit.Unit__r.Floor__c
                    };
                });
                this.newSelectedList = newSelectedList;
                console.log('newSelectedList ===> ' + JSON.stringify(this.newSelectedList));

                let selectedPricingElements = [];
                if(Array.isArray(result.costSheetTemObj.Cost_Pricings_Association__r)){
                    selectedPricingElements = result.costSheetTemObj.Cost_Pricings_Association__r.map(pricing => pricing.Pricing_Element_Master__c);
                }
                this.selectedPricingElementList = selectedPricingElements;
                console.log('selectedPricingElements ===> ' + JSON.stringify(this.selectedPricingElementList));

                if(result.picklistResult != null){
                    this.processPicklistValues(result.picklistResult);
                }
                this.projectOptions = result.projectList.map(value => ({label: value.Name, value: value.Id}));
                this.selectedFloor = result.selectedFloor;
                this.selectedTower = result.selectedTower;
                this.processTowerFloorDetails(result.unitWrp);
                console.log('taxMaster ==> ' + JSON.stringify(this.taxMasterList));
                
                if(this.selectedTower != null){
                    if (this.floorList) {
                        this.floorOptions = this.floorList.filter(floor => 
                            floor.Block__c === this.selectedTower 
                        ).map(floor => ({ label: floor.Floor_No__c, value: floor.Id }));
                    }
                }
                // this.unitListformatted = this.unitList.filter(unit => this.selectedUnitsList.includes(unit.Id));
                // this.unitListformatted = this.unitList.filter(unit => unit.Floor__c === this.selectedFloor);

                if(this.lockRecord == true){
                    this.unitListformatted = this.unitListformatted.map(item => ({
                        ...item,
                        isChecked: this.selectedUnitsList.includes(item.Id)
                    }));
                }else{
                    // this.unitListformatted = this.unitList.filter(unit => this.selectedUnitsList.includes(unit.Id));
                    this.unitListformatted = this.unitList.filter(unit => unit.Floor__c === this.selectedFloor);
                    
                }
                

                this.pricingElementList = this.pricingElementList.map(item => ({
                    ...item,
                    isChecked : this.selectedPricingElementList.includes(item.Id)
                }));
                
                this.newUnitFormattedList = this.unitListformatted.map(unit => ({
                    Id: unit.Id,
                    Name: unit.Unit_Name__c,
                    Block: unit.Floor__r.Block__r.Block_Code__c,
                    Floor: unit.Floor__r.Floor_No__c
                }));
                

                this.selectedUnitsToDisplay = this.unitList.filter(unit => this.selectedUnitsList.includes(unit.Id));
                // if(this.selectedUnitsToDisplay){
                //     setTimeout(() => this.template.querySelector('c-custom-pagination-comp').setPagination(5));
                // }
                // this.selectedUnitsToDisplay = selectedUnitsToDisplay.map(unit => ({
                //     Id: unit.Id,
                //     Name: unit.Unit_Name__c,
                //     Block: unit.Floor__r.Tower__r.Tower_Code__c,
                //     Floor: unit.Floor__r.Floor_No__c
                // }));
                // if(this.newUnitFormattedList){
                //     setTimeout(() => this.template.querySelector('c-custom-pagination-comp').setPagination(5));
                // }

                for(const pricingEle of this.pricingElementList){
                    var relatedPricingAssociationWithTax = result.costPricingAssociationWithTax.find(item => item.Pricing_Element_Master__c === pricingEle.Id );
                    console.log('relatedPricingAssociationWithTax ===> ' + JSON.stringify(relatedPricingAssociationWithTax));
                    
                    let taxList = [];
                    if(relatedPricingAssociationWithTax){
                        if(relatedPricingAssociationWithTax.Cost_Sheet_Tax_Linkings__r && Array.isArray(relatedPricingAssociationWithTax.Cost_Sheet_Tax_Linkings__r)){
                            for(const association of relatedPricingAssociationWithTax.Cost_Sheet_Tax_Linkings__r){
                                console.log('association ===> ' + JSON.stringify(association));
                                var taxOptions = this.taxMasterList.filter(item => item.Tax_Type__c === association.Tax_Master__r.Tax_Type__c).map(tax => ({ label: tax.Name, value: tax.Id }));
                                const newTax = {
                                    CPAId           : association.Id != null ? association.Id : null, 
                                    Id              : association.Tax_Master__c != null ? association.Tax_Master__c : null,
                                    Tax_Type__c     : association.Tax_Master__r.Tax_Type__c != null ? association.Tax_Master__r.Tax_Type__c : null,
                                    Tax__c          : association.Tax_Master__r.Tax__c != null ? association.Tax_Master__r.Tax__c : null, 
                                    App__c          : association.App__c != null ? association.App__c : '', 
                                    Name            : association.Tax_Master__c != null ? association.Tax_Master__c : null,
                                    Amount__c       : association.Amount__c != null ? association.Amount__c : '',
                                    index           : taxList.length === 0 ? 1 : taxList.length + 1, 
                                    taxOptions      : taxOptions ? taxOptions : null, 
                                    parentPricingId : pricingEle.Id
                                };
                                taxList.push(newTax);
                            }
                        }
                        
                        if(taxList.length === 0){
                            taxList.push({CPAId : '', Id : '', Tax_Type__c: '', Tax__c: '', App__c: '', Name: '', Amount__c: '', index: 1, taxOptions: [], parentPricingId: pricingEle.Id, roundingMethod : '', showCheck : false});
                        }
                        
                        const newAssociation = {
                            Id                          : relatedPricingAssociationWithTax.Id != null ? relatedPricingAssociationWithTax.Id : null,
                            Pricing_Element_Master__c   : pricingEle.Id != null ? pricingEle.Id : null,
                            Name                        : pricingEle.Name != null ? pricingEle.Name : null,
                            Agreement__c                : pricingEle.Agreement__c == true ? true : false,
                            Unit__c                     : relatedPricingAssociationWithTax.Unit__c != null ? relatedPricingAssociationWithTax.Unit__c : null,
                            PE_Type__c                  : relatedPricingAssociationWithTax.PE_Type__c != null ? relatedPricingAssociationWithTax.PE_Type__c : null,
                            Type__c                  : relatedPricingAssociationWithTax.Type__c != null ? relatedPricingAssociationWithTax.Type__c : null,
                            Sequence__c                 : relatedPricingAssociationWithTax.Sequence__c != null ? relatedPricingAssociationWithTax.Sequence__c : '',
                            Quantity__c                 : relatedPricingAssociationWithTax.Quantity__c != null ? relatedPricingAssociationWithTax.Quantity__c : '',
                            Rate__c                     : relatedPricingAssociationWithTax.Rate__c != null ? relatedPricingAssociationWithTax.Rate__c : '',
                            Amount__c                   : relatedPricingAssociationWithTax.Amount__c != null ? parseFloat(relatedPricingAssociationWithTax.Amount__c) : '',
                            Tax_Amount__c               : relatedPricingAssociationWithTax.Tax_Amount__c != null ? parseFloat(relatedPricingAssociationWithTax.Tax_Amount__c) : '',
                            taxList                     : taxList,
                            No_Of_Taxs                  : taxList.length > 0 ? taxList.length : 0
                        };

                        if(pricingEle.isChecked === true){
                            console.log(' pricing exists => ' + pricingEle.id);
                            this.costPricingAssociationsList.push(newAssociation);
                        }
                        this.originalCostPricingAssociationsList = this.costPricingAssociationsList;
                        console.log('this.costPricingAssociationsList ===> ' + JSON.stringify(this.costPricingAssociationsList));
                        // setTimeout(() => this.template.querySelector('c-custom-pagination-comp').setPagination(5));
                    }
                }
                
                
                this.secondNext = true;
                this.firstNext = true;
                this.showPricingLowerDiv = true;
                this.showAccordians = true;
                this.showPricingElement = true;
                setTimeout(() => this.template.querySelector('c-custom-pagination-comp').setPagination(5));
                this.showProjectUnitAllocation = true;
                this.displayUnitRecords = true;
                // if(this.selectedUnitsList.length > 0){
                //     this.template.querySelector('lightning-datatable').selectedRows = this.selectedUnitsList;
                // }

                if(this.lockRecord == false){
                    this.currentPage = 1;
                    this.initializePagination();
                }
            }
        })
        .catch(error => {
            console.log('Error while fetching data ===> ' + error);
        });
    }

    get lockedNonEditable(){
        const disabledMode = (this.editRecord == true && this.lockRecord == true) ? true : false;
        console.log('disabledMode ===> ' + disabledMode);
        return disabledMode;
    }

    get containsSoldUnitsList(){
        return this.soldUnitsList.length > 0 ? true : false;
    }

    get displayMainUnitsList(){
        return this.newUnitFormattedList.length > 0 ? true : false;
    }

    get newRecord(){
        const hasRecordId = (this.recordId != null && this.recordId != '') ? true : false;
        const newMode = (this.editRecord == true && this.lockRecord == false) ? true : false;
        const finalMode = (newMode == true || hasRecordId == false) ? true : false;
        return finalMode;
    }

    handleCancel(){
        if(this.recordId != null && this.recordId != ''){
            const recordId = this.recordId;
            window.top.location.href = `/lightning/r/Cost_Sheet_Template__c/${recordId}/view`;
        }else{
            window.top.location.href = '/lightning/o/Cost_Sheet_Template__c/list';
        }
    }

    @track newSelectedList = [];
    handleRowSelection(event) {
        debugger;
        const selectedRows = event.detail.selectedRows;
        // if(selectedRows.length === 0){
        //     this.selectedUnitsList = [];
        // }
        
        if(selectedRows.length > 0){
            for(let i=0; i<selectedRows.length; i++){
                if(!this.selectedUnitsList.includes(selectedRows[i].Id)){
                    this.selectedUnitsList.push(selectedRows[i].Id);
                }
            }

            var newSelectedList = selectedRows;
            this.newSelectedList = newSelectedList;

            const paginatedUnitsIds = this.paginatedData.map(row => row.Id);
            const selectedPaginatedUnitIds = paginatedUnitsIds.filter(unitId => this.selectedUnitsList.includes(unitId));
            const actualPaginatedUnitIds = selectedRows.map(row => row.Id);
            const deselectedUnitIds = selectedPaginatedUnitIds.filter(unitId => !actualPaginatedUnitIds.includes(unitId));
            this.selectedUnitsList = this.selectedUnitsList.filter(id => !deselectedUnitIds.includes(id));

            // const filteredUnitIds = this.unitListformatted.filter(unit => unit.Status__c !== 'Sold').map(unit => unit.Id);
            // // const selectedUnitIds = selectedRows.map(row => row.Id);
            // const selectedUnitIds = filteredUnitIds.filter(unitId => this.selectedUnitsList.includes(unitId));
            // const deselectedUnitIds = filteredUnitIds.filter(unitId => !selectedUnitIds.includes(unitId));
            // this.selectedUnitsList = this.selectedUnitsList.filter(id => !deselectedUnitIds.includes(id));
            if(this.selectedUnitsList.length > 0){
                this.template.querySelector('lightning-datatable').selectedRows = this.selectedUnitsList;
            }

            console.log('selectedUnitsList ===> ' + JSON.stringify(this.selectedUnitsList));
            this.selectedUnitsToDisplay = this.unitList.filter(unit => this.selectedUnitsList.includes(unit.Id));
        }
    }

    @track paginatedData = []; 
    @track selectedUnitsList = []; 
    @track currentPage = 1;
    @track pageSize = 5; 
    @track totalPages = 0;

    initializePagination() {
        debugger;
        this.totalPages = Math.ceil(this.newUnitFormattedList.length / this.pageSize);
        this.updatePaginatedData();
    }

    updatePaginatedData() {
        debugger;
        console.log('selectedUnitsList ===> ' + JSON.stringify(this.selectedUnitsList));
        const startIndex = (this.currentPage - 1) * this.pageSize;
        const endIndex = startIndex + this.pageSize;
        this.paginatedData = this.newUnitFormattedList.slice(startIndex, endIndex);
        const selectedUnits = this.selectedUnitsList;
        if(selectedUnits.length > 0){
            this.template.querySelector('lightning-datatable').selectedRows = selectedUnits;
        }
    }

    handlePrevious() {
        debugger;
        if (this.currentPage > 1) {
            this.currentPage--;
            this.updatePaginatedData();
        }
    }

    handleNext() {
        debugger;
        if (this.currentPage < this.totalPages) {
            this.currentPage++;
            this.updatePaginatedData();
        }
    }

    get isFirstPage() {
        return this.currentPage === 1;
    }

    get isLastPage() {
        return this.currentPage === this.totalPages;
    }


    addRow(event) {
        debugger;
        const pricingid = event.target.dataset.pricingid;
        const costPricingAssociation = this.costPricingAssociationsList.find(item => item.Pricing_Element_Master__c === pricingid);

        if(costPricingAssociation){
            const taxElement = costPricingAssociation.taxList;
            const newTax = {
                CPAId : '', Id : '', Tax_Type__c : '',Tax__c : '', App__c : '', Name : '', Amount__c : '', index : 1, taxOptions : [], parentPricingId : pricingid, roundingMethod : '', showCheck : false
            };
            if(taxElement === 0){
                taxElement.push(newTax);
                
            }else{
                const taxListLength = taxElement;
                const lastTaxRec = taxElement[taxElement.length - 1];
                const index = lastTaxRec.index;
                newTax.index = index + 1;
                taxElement.push(newTax);
            }
            costPricingAssociation.taxList = taxElement;
            
        }
        console.log('this.costPricingAssociationsList ===> ' + JSON.stringify(this.costPricingAssociationsList));
    }

    handleDeleteAction(event) {
        debugger;
        const index = parseInt(event.target.dataset.id, 10);
        const pricingid = event.target.dataset.pricingid;
        const pricingElement = this.costPricingAssociationsList.find(item => item.Pricing_Element_Master__c === pricingid);
        if (pricingElement) {
            var taxElement = pricingElement.taxList;
            if(taxElement.length === 1){
                this.showErrorTop = false;
                taxElement = [{
                    CPAId : '', Id : '', Tax_Type__c : '',Tax__c : '', App__c : '', Name : '', Amount__c : '', index : 1, taxOptions : [], parentPricingId : pricingid, roundingMethod : ''
                }];

                this.costPricingAssociationsList = this.costPricingAssociationsList.map(item => 
                    item.Pricing_Element_Master__c === pricingid ? {...item, Tax_Amount__c : 0, taxList : taxElement, No_Of_Taxs: 1} : item
                );
                // this.showToast('Error', 'Atleast one tax element has to be present!!!', 'error');
                return;
            }else{
                if (taxElement) {
                    pricingElement.taxList = taxElement.filter(item => item.index !== index);
                    console.log('length of tax after deleting ===> ' + pricingElement.taxList.length);
                    var newTaxAmount = pricingElement.Amount__c / pricingElement.taxList.length;
                    pricingElement.taxList = pricingElement.taxList.map(item => {
                        return {...item,
                            Amount__c : (newTaxAmount * item.Tax__c) / 100
                        }
                    });
                    let afterDeletionTaxAmount = pricingElement.taxList.reduce((sum, item) => sum + item.Amount__c, 0);
                    this.costPricingAssociationsList = this.costPricingAssociationsList.map(item =>
                        item.Pricing_Element_Master__c === pricingid ? { ...item, taxList: [...pricingElement.taxList],
                                Tax_Amount__c : afterDeletionTaxAmount != null ? afterDeletionTaxAmount : 0,
                                No_Of_Taxs : pricingElement.taxList.length
                         } : item
                    );
                }
            }
        }
        console.log('costPriceAssociation ===> ' + JSON.stringify(this.costPricingAssociation));
    }

    handleDuplication(event){
        debugger;
        const index = parseInt(event.target.dataset.id, 10);
        const pricingid = event.target.dataset.pricingid;
        const pricingElement = this.costPricingAssociationsList.find(item => item.Pricing_Element_Master__c === pricingid);

        if (pricingElement && Array.isArray(pricingElement.taxList) && pricingElement.taxList.length > 0) {
            const taxElement = pricingElement.taxList.find(item => item.index === index);

            if (taxElement != null) {
                this.costPricingAssociationsList = this.costPricingAssociationsList.map(item => {
                    const pricingAmount = item.Amount__c;
                    if(Array.isArray(item.taxList)){
                        const isTaxAlreadyPresent = item.taxList.some(tax => tax.Id === taxElement.Id);
                        const taxForRounding = (taxElement.Tax__c * pricingAmount) / 100;

                        if(item.taxList.length === 1 && !isTaxAlreadyPresent && (item.taxList[0].Id == null || item.taxList[0].Id == '')){
                            item.taxList = item.taxList.map(tax => {
                                return {
                                    ...tax,
                                    Id : taxElement.Id,
                                    Tax_Type__c : taxElement.Tax_Type__c,
                                    Tax__c : taxElement.Tax__c,
                                    App__c : taxElement.App__c,
                                    Name : taxElement.Name,
                                    index : 1,
                                    taxOptions : taxElement.taxOptions,
                                    roundingMethod : taxElement.roundingMethod,
                                    showCheck : false,
                                    Amount__c : taxElement.roundingMethod == 'Nearest Currency' ? Math.round(taxForRounding) : taxElement.roundingMethod == 'Next Currency' ? Math.ceil(taxForRounding) : taxForRounding
                                };
                            });
                        }else if(item.taxList.length >= 1 && !isTaxAlreadyPresent ){
                            item.taxList.push({
                                Id : taxElement.Id,
                                Tax_Type__c : taxElement.Tax_Type__c,
                                Tax__c : taxElement.Tax__c,
                                App__c : taxElement.App__c,
                                Name : taxElement.Name,
                                index : item.taxList.length + 1,
                                taxOptions : taxElement.taxOptions,
                                roundingMethod : taxElement.roundingMethod,
                                showCheck : false,
                                Amount__c : taxElement.roundingMethod == 'Nearest Currency' ? Math.round(taxForRounding) : taxElement.roundingMethod == 'Next Currency' ? Math.ceil(taxForRounding) : taxForRounding
                            });
                        }
                    }
                    item.Tax_Amount__c = item.taxList.reduce((sum, tax) => sum + (tax.Amount__c || 0), 0);
                    item.taxList = item.taxList.map(tax => ({
                        ...tax,
                        showCheck : false
                    }));
                    return item;
                }); 
            }
        }
    }

    handleTaxChange(event) {
        debugger;
        const index = parseInt(event.target.dataset.index, 10); 
        const pricingid = event.target.dataset.pricingid;
        const name = event.target.name;
        const value = event.target.value;
        const pricingAmount = event.target.dataset.pricingamount;
        // const taxAmount = event.target.dataset.taxamount;
        const pricingElement = this.costPricingAssociationsList.find(item => item.Pricing_Element_Master__c === pricingid);
        if (pricingElement) {
            let taxList = pricingElement.taxList; 
            let currentTaxRec = taxList[index - 1];
            let taxLength = taxList.length;
            // let taxAmount = pricingElement.Amount__c / taxLength;

            if(name === 'Tax_Type__c'){
                currentTaxRec.Tax_Type__c = value;
                console.log('this.taxMasterList ===> ' + this.taxMasterList);
                var taxOptions = [
                    {label: 'None', value : null},
                    ...this.taxMasterList.filter(item => item.Tax_Type__c === value).map(tax => ({ label: tax.Name, value: tax.Id }))
                ];
                currentTaxRec.taxOptions = taxOptions;
                // if(taxLength > 0){
                //     pricingElement.Tax_Amount__c = taxAmtPricing;
                // }
            }else if(name === 'Name'){
                const selectedTaxFromList = taxList.find(item => item.Name === value);
                const selectedTax = this.taxMasterList.find(item => item.Id === value);

                if(selectedTaxFromList != null){
                    this.showToast('Error', 'Tax Already Selected !!!', 'error');
                    currentTaxRec.Name = 'None';
                    currentTaxRec.Id = null;
                    currentTaxRec.roundingMethod = '';
                    return;
                }else{
                    currentTaxRec.roundingMethod = selectedTax.Rounding_Method__c != null ? selectedTax.Rounding_Method__c : '';
                    currentTaxRec.Name = value;
                    currentTaxRec.Id = value;
                }
                
                currentTaxRec.Tax__c = selectedTax.Tax__c != null ? selectedTax.Tax__c : '';
                let taxForRounding = (currentTaxRec.Tax__c * pricingAmount) / 100;
                currentTaxRec.Amount__c =   currentTaxRec.roundingMethod == 'Nearest Currency' ? Math.round(taxForRounding) :
                                            currentTaxRec.roundingMethod == 'Next Currency' ? Math.ceil(taxForRounding) : taxForRounding;
                currentTaxRec.showCheck = true;
                let taxAmtPricing = taxList.reduce((sum, item) => sum + item.Amount__c, 0);
                if(taxLength > 0){
                    pricingElement.Tax_Amount__c = taxAmtPricing;
                }
            }else if(name === 'App__c'){
                currentTaxRec.App__c = value;
            }
            
            pricingElement.taxList = [...taxList];
            this.costPricingAssociationsList = this.costPricingAssociationsList.map(item => 
                item.Pricing_Element_Master__c === pricingid ? { ...item, taxList: pricingElement.taxList } : item
            );
        }
    }
    
    
    @track costPricingAssociationsList = [];
    handleCostPriceAssociation(event) {
        debugger;
        const name = event.target.name; 
        const value = event.target.value; 
        const pricingid = event.target.dataset.pricingid;
        var existingAssociation = this.costPricingAssociationsList.find(item => item.Pricing_Element_Master__c === pricingid);    
        console.log('existingAssociation ===> ' + existingAssociation);
            
        this.costPricingAssociationsList.forEach(item => {
            if (item.Pricing_Element_Master__c === pricingid) {
                item[name] = value; 
                if (name === 'Quantity__c' || name === 'Rate__c') {
                    const quantity = parseFloat(item.Quantity__c) || 0; 
                    const rate = parseFloat(item.Rate__c) || ''; 
                    item.Amount__c = (quantity * rate).toFixed(2); 
                    item.Tax_Amount__c = 0; 

                    if(Array.isArray(item.taxList)){
                        item.taxList.forEach(tax => {
                            const taxForRounding = (tax.Tax__c * item.Amount__c) / 100;
                            tax.Amount__c = tax.roundingMethod === 'Nearest Currency' ? Math.round(taxForRounding) : tax.roundingMethod === 'Next Currency' ? Math.ceil(taxForRounding) : taxForRounding;
                        });

                        item.Tax_Amount__c = item.taxList.reduce((sum, tax) => sum + parseFloat(tax.Amount__c || 0), 0 );
                    }
                }
            }
        });
        this.costPricingAssociationsList = [...this.costPricingAssociationsList];
    }

    @track newUnitFormattedList = [];
    @track soldUnitsList = [];
    handleChangeTowerFloor(event) {
        debugger;
        var name = event.target.name;
        var value = event.target.value;
        if (name === 'Block__c') {
            this.selectedTower = value;
            if (this.floorList) {
                this.floorOptions = this.floorList.filter(floor => 
                    floor.Block__c === this.selectedTower 
                ).map(floor => ({ label: floor.Floor_No__c, value: floor.Id }));
            } else {
                this.floorOptions = []; 
            }
        }else if(name === 'Floor__c'){
            this.selectedFloor = value;
            this.unitListformatted = this.unitList.filter(unit => unit.Floor__c === this.selectedFloor);
            console.log('this.unitListformatted ===> ' + JSON.stringify(this.unitListformatted));     
            this.newUnitFormattedList = this.unitListformatted.filter(unit => unit.Status__c !== 'Z1').map(unit => ({
                Id: unit.Id,
                Name: unit.Unit_Name__c,
                Block: unit.Floor__r.Block__r.Block_Code__c,
                Floor: unit.Floor__r.Floor_No__c
            }));
            this.soldUnitsList = this.unitListformatted.filter(unit => unit.Status__c === 'Z1');  
            if(this.newUnitFormattedList.length > 0){
                this.currentPage = 1;
                this.initializePagination();
            }else{
                this.newUnitFormattedList = [];
            }
        }
        this.displayUnitRecords = (this.selectedFloor != null && this.selectedTower != null) ? true : false;
        
    }

    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
        });
        this.dispatchEvent(event);
    }

    validateCode() {
        debugger;
        checkIfTemplateCodeExists({ costSheetTempCode: this.costSheetTemObj.Template_Code__c })
            .then(result => {
                this.templateCodeValidation = result
                if(this.templateCodeValidation == true){
                    this.showToast('Error', 'Template Code already exists, Please give a different Template Code to Proceed!!!', 'error');
                    return;
                }else{
                    if(this.templateCodeValidation == false && this.secondNext == false && this.showPricingLowerDiv == false && this.firstNext == true){
                        if(this.selectedPricingElementList.length == 0){
                            this.showErrorTop = true;
                            this.showToast('Error', 'Select atleast one Pricing Element!!!', 'error');
                            return;
                        }else if(this.newSelectedList.length == 0){
                            this.showErrorTop = true;
                            this.showToast('Error', 'Select atleast one Unit!!!', 'error');
                            return;
                        }else{
                            this.showPricingLowerDiv = true;
                            this.secondNext = true;
                            this.firstNext = false;
                            // setTimeout(() => this.template.querySelector('c-custom-pagination-comp').setPagination(5));
                            // this.getAllPicklistValues();
                        }
                    }
                    if(this.templateCodeValidation == false && this.firstNext == false && this.showAccordians == false){
                        // this.fetchPricingElements();
                        this.showAccordians = true;
                        this.firstNext = true;
                    }
                }
            })
            .catch(error => {
                return;
            });
    }

    @track templateCodeValidation = false;
    projectUnitAllocationPricingElement(){
        debugger;

        if(this.costSheetTemObj.Company__c == '' || this.costSheetTemObj.Project__c == '' || this.costSheetTemObj.Name == '' || this.costSheetTemObj.Template_Code__c == ''){
            this.showErrorTop = true;
            this.showToast('Error', 'Fill all the mandatory fields!!!', 'error');
            return;
        }
        
        if(this.costSheetTemObj.Template_Code__c && this.lockRecord == false && (this.recordId == null || this.recordId == '') ){
            this.validateCode();
            console.log('templateCodeValidation ===> ' + this.templateCodeValidation);
        }
    }

    fetchPricingElements(){
        debugger;
        getTowerFloorUnitPricingElementData({ projectId : this.costSheetTemObj.Project__c})
        .then(result => {
            if(result){
                this.processTowerFloorDetails(result);
            }
        })
        .catch(error => {
            console.log('Error fetching pricing elements ===> ' + error);
        });
    }

    @track searchedPricingEle = '';
    @track searchedPricingAsstn = '';
    handleKeyUp(evt) {
        debugger;
        // const isEnterKey = evt.keyCode === 13;
        const type = evt.currentTarget.dataset.type;
        // if (isEnterKey) {
            if(type == 'pricingEle'){
                this.searchedPricingEle = evt.target.value;
                if(this.searchedPricingEle != null && this.searchedPricingEle != ''){
                    this.fetchSearchedPricingElement(type);
                }else{
                    this.pricingElementList = this.pricingElementListMain;
                    setTimeout(() => this.template.querySelector('c-custom-pagination-comp').setPagination(5));
                }
            }else if(type == 'pricingAsstn'){
                this.searchedPricingAsstn = evt.target.value;
                this.costPricingAssociationsList = this.originalCostPricingAssociationsList.filter(item => 
                    item.Name && item.Name.toLowerCase().includes(this.searchedPricingAsstn.toLowerCase())
                );
                // setTimeout(() => this.template.querySelector('c-custom-pagination-comp').setPagination(5));
                // if(this.searchedPricingAsstn != null ||this.searchedPricingAsstn != ''){
                    
                // }else{
                //     this.costPricingAssociationsList = this.originalCostPricingAssociationsList;
                //     setTimeout(() => this.template.querySelector('c-custom-pagination-comp').setPagination(5));
                // }
                
            } 
        // }
    }

    fetchSearchedPricingElement(type){
        debugger;
        if(type == 'pricingEle'){
            fetchPricingBasedonSearch({ searchedPricingEle : this.searchedPricingEle })
            .then(result => {
                if(result.length > 0){
                    this.pricingElementList = result;
                    setTimeout(() => this.template.querySelector('c-custom-pagination-comp').setPagination(5));
                }else{
                    this.pricingElementList = [];
                }
            })
            .catch(error => {
                console.log('Error ==> ' + error);
            })
        }
    }

    @track pricingElementListMain = [];
    processTowerFloorDetails(result){
        debugger;
        this.pricingElementList = result.pricingElementList.length > 0 ? result.pricingElementList : null;
        this.pricingElementList = this.pricingElementList.map(item => ({
            ...item,
            isChecked : false
        }));
        this.pricingElementListMain = this.pricingElementList;
        
        // this.pricingElementList = result.pricingElementList.map(item => ({
        //     ...item,
        //     isChecked : this.selectedUnitsList.includes(item.Id) ? true : false
        // }));


        // this.pricingElementList.forEach(element => {
        //     this.selectedPricingElementList.push(element.Id); 
        //     const newAssociation = {
        //         Pricing_Element_Master__c: element.Id,
        //         Agreement__c : element.Agreement__c,
        //         Name : element.Name,
        //         Unit__c: '',  
        //         PE_Type__c: '', 
        //         Quantity__c: 1, 
        //         Rate__c: 0,    
        //         Amount__c: 0,  
        //         Tax_Amount__c: 0 
        //     };
        //     this.costPricingAssociationsList.push(newAssociation);
        // });
        this.BlockList = result.BlockList != null ? result.BlockList : null;
        if(this.BlockList != null){
            this.towerOptions = this.BlockList.map(value => ({label: value.Block_Code__c, value: value.Id}));
        }
        this.floorList = result.floorList != null ? result.floorList : null;
        this.unitList = result.unitList != null ? result.unitList : null;
        this.taxMasterList = result.taxMasterList != null ? result.taxMasterList : null;
        // this.taxListformatted = this.taxMasterList.map(tax => ({
        //     Id: tax.Id,
        //     Tax__c : tax.Tax__c,
        //     Name : tax.Name
        // }));
    }

    // @track selectedPricingIds = [];
    allSelected(event) {
        debugger;
        // const isAllSelected = event.target.checked;
        let selectedRows = this.template.querySelectorAll('lightning-input');
        for (let i = 0; i < selectedRows.length; i++) {
            if(selectedRows[i].type === 'checkbox' && selectedRows[i].dataset.table === 'pricingElements') {
                selectedRows[i].checked = event.target.checked;
                var selectedId = selectedRows[i].dataset.id;
                if (selectedRows[i].checked) {
                    if (selectedId && !this.selectedPricingElementList.includes(selectedId)) {
                        this.selectedPricingElementList.push(selectedId);
                        const element = this.pricingElementList.find(el => el.Id === selectedId);
                        if(element){
                            const newTax = {
                                CPAId : '', Id : '', Tax_Type__c : '',Tax__c : '', App__c : '', Name : '', Amount__c : '', index : 1, taxOptions : [], parentPricingId : element.Id, roundingMethod : '', showCheck : false
                            };
                            const newAssociation = {
                                Id : '',
                                Pricing_Element_Master__c: element.Id,
                                Agreement__c: element.Agreement__c || false, 
                                Name: element.Name || '', 
                                Unit__c: element.Conversion_Unit__c != null ? element.Conversion_Unit__c : '', 
                                PE_Type__c: '', 
                                Type__c: 'Agreement', 
                                Quantity__c: 1,
                                Sequence__c:'', // what we need to do with this?,
                                Rate__c: '',
                                Amount__c: '',
                                Tax_Amount__c: '',
                                taxList : [newTax],
                                No_Of_Taxs : 0
                            };
                            this.costPricingAssociationsList.push(newAssociation);
                        }
                    }
                } else {
                    const index = this.selectedPricingElementList.indexOf(selectedId);
                    if (index >= 0) {
                        this.selectedPricingElementList.splice(index, 1);
                        this.costPricingAssociationsList = this.costPricingAssociationsList.filter(
                            association => association.Pricing_Element_Master__c !== selectedId
                        );
                    }
                }
            }
        }
        this.pricingElementList = this.pricingElementList.map(item => ({
            ...item,
            isChecked : this.selectedPricingElementList.includes(item.Id)
        }));
        this.originalCostPricingAssociationsList = this.costPricingAssociationsList;
        console.log('this.selectedPricingElementList ===> ' + this.selectedPricingElementList);
        console.log('this.costPricingAssociationsList ===> ' + JSON.stringify(this.costPricingAssociationsList));
    }

    handleCheckboxChange(event) {
        debugger;
        const id = event.target.dataset.id;
        const Agreement__c = event.target.dataset.agreement;
        const Name = event.target.dataset.name;
        const checked = event.target.checked;
        const unitValue = event.target.unit;
        
        if (checked) {
            this.selectedPricingElementList.push(id);
            console.log('selectedPricingElementList ===> ' + JSON.stringify(this.selectedPricingElementList));
            
            this.pricingElementList = this.pricingElementList.map(item => ({
                ...item,
                isChecked : this.selectedPricingElementList.includes(item.Id)
            }));
            const newTax = {
                CPAId : '', Id : '', Tax_Type__c : '',Tax__c : '', App__c : '', Name : '', Amount__c : '', index : 1, taxOptions : [], parentPricingId : id, roundingMethod : '', showCheck : false
            };
            const newAssociation = {
                Id : '',
                Pricing_Element_Master__c: id,
                Name : Name,
                Agreement__c : Agreement__c,
                Unit__c: unitValue != null ? unitValue : '',
                PE_Type__c: '',
                Type__c: 'Agreement',
                Quantity__c: 1,
                Rate__c: '',
                Amount__c: '',
                Tax_Amount__c: '',
                taxList : [newTax],
                No_Of_Taxs : 0
            };
            this.costPricingAssociationsList.push(newAssociation);
        } else {
            const index = this.selectedPricingElementList.indexOf(id);
            // if (index > -1) {
            if (index != null) {
                this.selectedPricingElementList.splice(index, 1);
                this.pricingElementList = this.pricingElementList.map(item => ({
                    ...item,
                    isChecked : this.selectedPricingElementList.includes(item.Id)
                }));
                this.costPricingAssociationsList = this.costPricingAssociationsList.filter(
                    item => item.Pricing_Element_Master__c !== id
                );
            }
        }
        this.originalCostPricingAssociationsList = this.costPricingAssociationsList;
        console.log('costPricingAssociationsList ===> ' + JSON.stringify(this.costPricingAssociationsList));
    }

    @track selectedUnitsList = [];
    allSelectedUnit(event) {
        debugger;
        let selectedRows = this.template.querySelectorAll('lightning-input');
        for(let i = 0; i < selectedRows.length; i++) {
            if(selectedRows[i].type === 'checkbox' && selectedRows[i].dataset.table === 'unitTable') {
                selectedRows[i].checked = event.target.checked;
                var selectedId = selectedRows[i].dataset.id;
                if (selectedRows[i].checked) {
                    if (selectedId && !this.selectedUnitsList.includes(selectedId)) {
                        this.selectedUnitsList.push(selectedId);
                    }
                } else {
                    const index = this.selectedUnitsList.indexOf(selectedId);
                    if (index > -1) {
                        this.selectedUnitsList.splice(index, 1);
                    }
                }
            }
        }
        console.log('this.selectedUnitsList ===> ' + this.selectedUnitsList);
    }

    handleCheckboxChangeUnit(event){
        debugger;
        const id = event.target.dataset.id;
        const checked = event.target.checked;
        if(checked) {
            this.selectedUnitsList.push(id);
        } else {
            const index = this.selectedUnitsList.indexOf(id);
            this.selectedUnitsList.splice(index, 1);
        }
        console.log('this.selectedUnitsList ===> ' + this.selectedUnitsList);
    }
    
    toggleSection(event) {
        debugger;
        const buttonid = event.currentTarget.dataset.buttonid;
        const section = this.template.querySelector(`[data-id="${buttonid}"]`);
        if (section.classList.contains('slds-is-open')) {
            section.classList.remove('slds-is-open');
            section.classList.add('slds-is-close');
        } else {
            section.classList.remove('slds-is-close');
            section.classList.add('slds-is-open');
        }
        
        if(buttonid == 1){
            this.showProjectUnitAllocation = false;
            this.showPricingElement = true;
            setTimeout(() => this.template.querySelector('c-custom-pagination-comp').setPagination(5));

        }else if(buttonid == 2){
            this.showProjectUnitAllocation = true;
            this.showPricingElement = false;
        }

        const otherSectionId = buttonid == 1 ? '2' : '1';
        const otherSection = this.template.querySelector(`[data-id="${otherSectionId}"]`);
        if (otherSection) {
            otherSection.classList.remove('slds-is-open');
            otherSection.classList.add('slds-is-close');
        }
    }

    getCompanyList(){
        debugger;
        getCompanyDetails()
        .then(result => {
            if(result){
                debugger;
                this.companyOptions = result.map(value => ({label: value.Name, value: value.Id}));
            }
        })
        .catch(error => {
            console.log('Error fetching dependant picklists ===> ' + error);
        });
    }

    handleChangeCostSheetTemp(event){
        debugger;
        var name = event.target.name;
        var value = event.target.type === 'checkbox' ? event.target.checked : event.target.value;
        this.costSheetTemObj = { ...this.costSheetTemObj, [name]: value };
        if (name === 'Company__c') {
            this.fetchProjectPicklists();
            // this.fetchProjectList();
        }
        if(name === 'Project__c'){
            this.fetchPricingElements();
        }
    }

    fetchProjectPicklists(){
        debugger;
        fetchProjectAndPicklistDetails({ companyId : this.costSheetTemObj.Company__c, ObjectByField: this.objByField })
        .then(result => {
            this.projectOptions = result.projectList ? result.projectList.map(value => ({label: value.Name, value: value.Id})) : null;
            if(result.picklistValByField){
                this.processPicklistValues(result.picklistValByField);
            }
        })
        .catch(error => {
            console.error('Error==>' + error);
        });
    }

    // fetchProjectList(){
    //     fetchProjectRecords({ companyId : this.costSheetTemObj.Company__c})
    //     .then(result => {
    //         if(result){
    //             this.projectOptions = result.map(value => ({label: value.Name, value: value.Id}));
    //         }
    //     })
    //     .catch(error => {
    //         console.log('Error fetching project records ===> ' + error);
    //     });
    // }
    
    @track PETypeOptions = [];
    @track UnitOptions = [];
    @track TypeOptions = [];
    @track taxTypeOptions = [];

    // getAllPicklistValues() {
    //     getAllPickListVal({ ObjectByField: this.objByField })
    //         .then(result => {
    //             this.processPicklistValues(result);
    //         })
    //         .catch(error => {
    //             console.error('Error==>' + error);
    //         });
    // }

    processPicklistValues(result){
        debugger;
        if(result){
            this.PETypeOptions = this.mapToLabelValuePair(result['PE_Type__c']);
            this.UnitOptions = this.mapToLabelValuePair(result['Unit__c']);
            this.TypeOptions = this.mapToLabelValuePair(result['Type__c']);
            this.taxTypeOptions = this.mapToLabelValuePair(result['Tax_Type__c']);
        }
    }

    mapToLabelValuePair(values) {
        return values.map(value => ({
            label: value, value: value
        }));
    }
}