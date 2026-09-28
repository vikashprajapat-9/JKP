import { LightningElement, api, track } from 'lwc';
import getOnLoadData from '@salesforce/apex/CostSheetGenerationController.getOnLoadData';
//import createCostSheet from '@salesforce/apex/CostSheetGenerationController.createCostSheet';
import saveCostSheet from '@salesforce/apex/CostSheetGenerationController.saveCostSheet';
import getPricingElements from '@salesforce/apex/CostSheetGenerationController.getPricingElements';
import getParkingRecords from '@salesforce/apex/CostSheetGenerationController.getParkingRecords';
//import createparkingElements from '@salesforce/apex/CostSheetGenerationController.createparkingElements';
//import updatePricingElements from '@salesforce/apex/CostSheetGenerationController.updatePricingElements';
import submitCostSheetForApproval from '@salesforce/apex/CostSheetGenerationController.submitCostSheetForApproval';
//import checkAccess from '@salesforce/apex/CostSheetGenerationController.checkAccess';
import getUnitRecord from '@salesforce/apex/CostSheetGenerationController.getUnitRecord';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { NavigationMixin } from 'lightning/navigation';
import modal from "@salesforce/resourceUrl/QuickActionCSS";
import { loadStyle } from "lightning/platformResourceLoader";

export default class CostSheetGeneration extends NavigationMixin(LightningElement) {
    unitList = [];
    unitOptions = [];
    templateOptions = [];
    @track filteredTemplateOptions = [];

    isDataLoaded = false;
    isUnitDisabled = false;
    isDropdownOpen = false;
    searchKey = '';
    selectedCostSchemeId = '';
    @track showErrorBlock = false;
    @track firstScreen = true;
    @track secondScreen = false;
    @track thirdScreen = false;
    @track fourthScreen = false;
    @track isNextDisabled = false;
    @track isFourthNextDisabled = false;
    @track isFianlSaveDisabled = false;
    @track newCostSheetId = '';
    @track pricingElements = [];
    @track duplicatepricingElements = [];
    @track totalAmount = 0;
    @track parkingDetails = {};
   // @track discountLineItem = [];
    @track realAmount = 0;
    @track taxAmount = 0;
    @track discountApplicable = 'No';
    @track discountAmount = 0;
    @track discountPercent = 0;
    @track discountedAmount = 0;
    @track discountedTotalAmount = 0;
    @track parkingDetailTable = false;
    @track selectedUnitRec = [];
    @track carParkingTax = {};
    costSheetData = {
        opp: null,
        tasks: null,
        unitId: null,
        cslId: null
    };

    _recordId;
    opp;
    get discountOptions() {
        return [
            { label: 'Yes', value: 'Yes' },
            { label: 'No', value: 'No' }
        ];
    }
    get isDiscountApplicable() {
        return this.discountApplicable === 'Yes';
    }
    get formattedDiscountAmount() {
        return new Intl.NumberFormat('en-IN', {
            maximumFractionDigits: 2
        }).format(this.discountAmount || 0);
    }
    get formattedDiscountedAmount() {
        return new Intl.NumberFormat('en-IN', {
            maximumFractionDigits: 2
        }).format(this.discountedAmount || 0);
    }
    get formattedDiscountedTotalAmount() {
        return new Intl.NumberFormat('en-IN', {
            maximumFractionDigits: 2
        }).format(this.discountedTotalAmount || 0);
    }
    get realAmountNumeric() {
        return parseFloat(this.totalAmount) || 0;
    }

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        if (value) {
            this.loadData();
        }
    }

    @track rows = [
        { id: 'row_1', type: '', amount: '', finalAmount: '', quantity: 1, carCGSTtax: '', carSGSTtax: '', taxAmt: '' }, // Initial row
    ];

    get defaultUnit() {
        debugger;
        if (this.selectedUnitId != null && this.isUnitDisabled == true) {
            return true;
        }
    }


    connectedCallback() {
        debugger;
        loadStyle(this, modal);
    }

    loadData() {
        getOnLoadData({ recordId: this._recordId })
            .then(data => {
                this.isDataLoaded = true;
                this.showErrorBlock = (data.errorMessage != null && data.errorMessage != '') ? true : false;
                this.opp = data.opp == null || data.opp == undefined ? null : data.opp;
                this.carParkingTax = data.carParkingTax == null || data.carParkingTax == undefined ? null : data.carParkingTax;
                this.rows.carCGSTtax = data.carParkingTax.CGST__c != null || data.carParkingTax.CGST__c != undefined ? data.carParkingTax.CGST__c : 0;
                this.rows.carSGSTtax = data.carParkingTax.SGST__c != null || data.carParkingTax.SGST__c != undefined ? data.carParkingTax.SGST__c : 0;
                if (this.opp.Unit__c) {
                    this.selectedUnitId = this.opp.Unit__c;
                    this.isUnitDisabled = true;
                    this.getUnitRecord();
                }
                this.unitList = data.unitList == undefined || data.unitList == null ? null : data.unitList;
                if (this.unitList) {
                    this.unitOptions = this.unitList.map(unit => ({ label: unit.Name, value: unit.Id }));
                }
                this.templateList = data.costSheetTemplateList == undefined || data.costSheetTemplateList == null ? null : data.costSheetTemplateList;
                this.filteredTemplate();
            })
            .catch(error => {
                this.showErrorBlock = true;
                console.error('FULL ERROR:', error);
                console.error('ERROR JSON:', JSON.stringify(error));
                console.error('BODY:', error?.body);
                console.error('MESSAGE:', error?.body?.message);
                this.showToast('Error', 'Failed to load data.', 'error');
            });
    }

    handleChangeUnit(event) {
        debugger;
        this.selectedUnitId = event.detail.id;
        console.log('selectedUnitId ===> ' + this.selectedUnitId);
        this.getUnitRecord();
        // this.selectedUnitId = event.detail.recordId;

    }

    getUnitRecord() {
        debugger;

        getUnitRecord({ unitId: this.selectedUnitId })
            .then(result => {
                console.log('Unit Record:', result);
                this.selectedUnitRec = result;
                this.filteredTemplate();
            })
            .catch(error => {
                console.error('Error fetching unit record:', error);
            });

    }
    handleDiscountApplicable(event) {
        this.discountApplicable = event.detail.value;

        if (this.discountApplicable === 'No') {
            this.discountAmount = 0;
            this.discountPercent = 0;
            this.discountedAmount = 0;
            this.discountedTotalAmount = 0;
            this.calculateTotals();
        } else {
            this.calculateDiscountedAmount();
        }
    }
    handleDiscountAmountChange(event) {
        let amount = parseFloat(event.target.value);
        if (isNaN(amount)) {
            this.discountAmount = 0;
            this.discountPercent = 0;
            this.discountedAmount = 0;
            this.discountedTotalAmount = 0;
            return;
        }
        const totalAmount = this.realAmountNumeric;
        if (amount < 0) {
            amount = 0;
        }
        if (amount > totalAmount) {
            this.showToast(
                'Error',
                'Discount Amount cannot be greater than Total Amount Exclusive of Taxes.',
                'error'
            );
            amount = totalAmount;
        }
        this.discountAmount = amount;
        if (amount === 0) {
            this.discountPercent = 0;
            this.discountedAmount = 0;
            this.discountedTotalAmount = 0;
            return;
        }
        this.discountPercent = ((amount / totalAmount) * 100).toFixed(2);
        this.calculateDiscountedAmount();
    }
    handleDiscountPercentChange(event) {
        let percent = parseFloat(event.target.value);
        // User cleared the input
        if (isNaN(percent)) {
            this.discountPercent = 0;
            this.discountAmount = 0;
            this.discountedAmount = 0;
            this.discountedTotalAmount = 0;
            return;
        }
        const totalAmount = this.realAmountNumeric;
        if (percent < 0) {
            percent = 0;
        }
        if (percent > 100) {
            this.showToast(
                'Error',
                'Discount Percentage cannot be greater than 100%.',
                'error'
            );
            percent = 100;
        }
        this.discountPercent = percent;
        if (percent === 0) {
            this.discountAmount = 0;
            this.discountedAmount = 0;
            this.discountedTotalAmount = 0;
            return;
        }
        this.discountAmount = ((totalAmount * percent) / 100).toFixed(2);
        this.calculateDiscountedAmount();
    }

    calculateDiscountedAmount() {
        const totalAmount = this.realAmountNumeric;
        const discountAmount = parseFloat(this.discountAmount) || 0;
        if (discountAmount <= 0) {
        this.discountedAmount = 0;
        this.discountedTotalAmount = 0;
        return;
    }

        this.discountedAmount = Math.max(
            totalAmount - discountAmount,
            0
        );

        this.calculateDiscountedTotalAmount();
    }
    calculateDiscountedTotalAmount() {
        const totalAmount = this.realAmountNumeric;
        const discountedAmount = parseFloat(this.discountedAmount) || 0;
        const originalTaxAmount =
            parseFloat(String(this.taxAmount).replace(/[^0-9.]/g, '')) || 0;

        if (totalAmount > 0) {

            const taxRatio = originalTaxAmount / totalAmount;

            const discountedTaxAmount =
                discountedAmount * taxRatio;

            this.discountedTotalAmount =
                discountedAmount + discountedTaxAmount;

        } else {

            this.discountedTotalAmount = 0;

        }
    }

    handleSearchChange(event) {
        debugger;
        this.searchKey = event.target.value;
        console.log('searchKey:', this.searchKey);
        console.log('templateOptions:', JSON.stringify(this.templateOptions));

        this.filteredTemplate(); // Re-filter templates based on the search term
        this.isDropdownOpen = true;
    }

    toggleDropdown() {
        debugger;
        this.isDropdownOpen = !this.isDropdownOpen;
    }

    handleOptionClick(event) {
        debugger;
        const selectedValue = event.currentTarget.dataset.value;
        this.selectedCostSchemeId = selectedValue;
        const selectedOption = this.filteredTemplateOptions.find(option => option.value === selectedValue);
        this.searchKey = selectedOption.label;
        this.isDropdownOpen = false;
    }

    filteredTemplate() {
        debugger;
        if (!this.templateList || this.templateList.length === 0) {
            this.filteredTemplateOptions = [];
            return;
        }
        console.log('this.templateList==>', this.templateList);

        this.filteredTemplateOptions = this.templateList.reduce((acc, template) => {

            const blockLinking = template.Cost_Scheme_Linkings__r || [];
            console.log('blockLinking==>' + JSON.stringify(blockLinking));
            const unitLinking = template.Cost_Unit_Linking__r || [];
            console.log('unitLinking==>' + JSON.stringify(unitLinking));
            if(template.Id == 'a0hBh000004BTkMIAW') debugger;
            console.log('Processing Template:', template.Name);

            for (var i = 0; i < blockLinking.length; i++) {
                console.log('blockLinking:', JSON.stringify(blockLinking[i]));
                for (var j = 0; j < unitLinking.length; j++) {
                    console.log('unitLinking:', JSON.stringify(unitLinking[j]));

                    const unitMatch = unitLinking[j].Unit__c === this.selectedUnitId;
                    let blockMatch = false;
                    let paymentSchemeBlockId = blockLinking[i]?.Payment_Scheme__r?.Block__c;
                    let selectedUnitBlockId = this.selectedUnitRec?.Floor__r?.Block__c;


                    if (this.selectedUnitRec !== undefined && this.selectedUnitRec.Status__c == 'Z0' && this.selectedUnitRec.Floor__r?.Block__c !== undefined) {
                        blockMatch = blockLinking[i]?.Payment_Scheme__r?.Block__c === this.selectedUnitRec.Floor__r.Block__c;
                    }

                    const label = `${template.Name} - ${blockLinking[i]?.Payment_Scheme__r?.Name || 'Unknown'}`;
                    const searchMatch = label.toLowerCase().includes(this.searchKey.toLowerCase());

                    console.log('Unit Linking Unit__c:', unitLinking[j]?.Unit__c);
                    console.log('Selected Unit Id:', this.selectedUnitId);
                    console.log('Unit Match:', unitMatch);

                    console.log('Payment Scheme:', blockLinking[i]?.Payment_Scheme__r?.Name);
                    console.log('Payment Scheme Block__c:', paymentSchemeBlockId);
                    console.log('Selected Unit Floor Block__c:', selectedUnitBlockId);
                    console.log('Block Match:', blockMatch);
                    console.log('Search:', this.searchKey);
                    console.log('Search Match:', searchMatch);
                    console.log('FINAL MATCH:',unitMatch && blockMatch && searchMatch);
                    if (unitMatch && blockMatch && searchMatch) {
                        acc.push({ label: label, value: `${blockLinking[i]?.Id || ''}` });
                    }
                }
            }
            return acc;
        }, []);
    }



    // handleNext() {
    //     debugger;
    //     console.log('this.opp==>' + this.opp);
    //     const parsedData = this.opp;

    //     // Extract the 'Id' value and assign it to a variable
    //     const oppId = parsedData.Id;

    //     checkAccess({ opp: oppId })
    //         .then(result => {
    //             if (result) {
    //                 debugger;
    //                 this.discountLineItem = result;
    //             } else if (result === 'ERROR') {
    //                 // this.showToast('Error', 'Cost Sheet record already exists with the same Cost Scheme Linking on this Opportunity.', 'error');
    //             }
    //         })
    //         .catch(error => {
    //             console.log('Error:', JSON.stringify(error));
    //             this.showToast('Error', 'Something went wrong!', 'error');
    //         });

    //     this.isNextDisabled = true;
    //     createCostSheet({ opp: this.opp, tasks: this.opp.Tasks, unitId: this.selectedUnitId, cslId: this.selectedCostSchemeId })
    //         .then(result => {
    //             this.loadData();
    //             if (result != 'ERROR') {
    //                 this.newCostSheetId = result;
    //                 this.isUnitDisabled = true;
    //                 this.showToast('Success', 'Cost Sheet record created successfully.', 'success');
    //                 this.isNextDisabled = false;
    //                 this.getPricingElements();
    //             } else if (result === 'ERROR') {
    //                 this.showToast('Error', 'Cost Sheet record already exists with the same Cost Scheme Linking on this Opportunity.1--', 'error');
    //                 this.isNextDisabled = false;
    //             }

    //         })
    //         .catch(error => {
    //             console.log('Error:', JSON.stringify(error));
    //             this.showToast('Error', 'Something went wrong!', 'error');
    //             this.isNextDisabled = false;
    //         });
    // }
    handleNext() {
        debugger;

        console.log('this.opp==>' + this.opp);

        this.costSheetData = {
            opp: this.opp,
            tasks: this.opp.Tasks,
            unitId: this.selectedUnitId,
            cslId: this.selectedCostSchemeId
        };

        console.log('costSheetData==>' + JSON.stringify(this.costSheetData));
        this.loadData();
        this.isNextDisabled = false;
        this.isUnitDisabled = true;
        this.getPricingElements();
    }

    getPricingElements() {
        debugger;
        getPricingElements({cslId: this.costSheetData.cslId, unitId: this.costSheetData.unitId })
            .then(result => {
                console.log('resultPricingElements JSON:', JSON.stringify(result));
                if (result && Array.isArray(result) && result.length > 0) {
                    this.pricingElements = result;
                    this.pricingElements = this.pricingElements.map(item => {
                        const originalRate = (item.Rate__c != null ? parseFloat(item.Rate__c) : 0) + (item.Discount_Amount__c != null ? parseFloat(item.Discount_Amount__c) : 0);
                        return { ...item, edit: false, originalRate: originalRate, ActualAmount: item.Amount__c != null ? item.Amount__c : 0, permanantTax: item.Final_Tax_Amount__c != null ? item.Final_Tax_Amount__c : 0, limitExceed: "" };
                    });
                    // console.log('discountLineItem:', JSON.stringify(this.discountLineItem));
                    // console.log('pricingElements:', JSON.stringify(this.pricingElements));

                    // for (var i = 0; i < this.discountLineItem.length; i++) {
                    //     for (var j = 0; j < this.pricingElements.length; j++) {
                    //         console.log('discount record:',JSON.stringify(this.discountLineItem[i]) );
                    //         console.log( 'pricing record:',JSON.stringify(this.pricingElements[j]) );
                    //         if (this.discountLineItem[i].Discount_Master__r.Pricing_Element_Master__c == this.pricingElements[j].Pricing_Element_Master__c) {
                    //             this.pricingElements[j].edit = true;
                    //         }
                    //     }

                    // }
                    console.log('this.pricingElements==>' + this.pricingElements);

                    this.totalAmount = this.pricingElements.reduce((sum, element) => {
                        return sum + (element.Amount__c || 0);
                    }, 0);
                    console.log('totalAmount:', this.totalAmount);
                    this.formattedTotalAmount = new Intl.NumberFormat('en-IN').format(this.totalAmount);

                    this.realAmount = this.formattedTotalAmount;
                    this.taxAmount = this.pricingElements.reduce((sum, element) => {
                        return sum + (element.Tax_Amount__c || 0);
                    }, 0);

                    this.totalAmount = this.totalAmount + this.taxAmount;
                    this.formattedTotalAmount = new Intl.NumberFormat('en-IN').format(this.totalAmount);
                    this.taxAmount = new Intl.NumberFormat('en-IN').format(this.taxAmount);

                    this.firstScreen = false;
                    this.secondScreen = true;

                    console.log('Pricing Elements:', JSON.stringify(this.pricingElements));
                    console.log('Pricing Elements:', JSON.stringify(this.pricingElements));



                } else if (result === 'ERROR') {
                    this.showToast('Error', 'Cost Sheet record already exists with the same Cost Scheme Linking on this Opportunity.2--', 'error');
                }// else {
                //     this.showToast('Info', 'No records found for the provided Cost Sheet ID.', 'info');
                // }

            })
            .catch(error => {
                console.error('CATCH ERROR:', error);
                console.error('Error body message:', error?.body?.message );
                console.log('Error:', JSON.stringify(error));
                this.showToast('Error', 'Something went wrong!', 'error');
            });

    }


    // handleDiscountChange(event) {
    //     debugger;
    //     const fieldName = event.target.dataset.field;
    //     const rowIndex = event.target.dataset.index;
    //     const value = parseFloat(event.target.value) || 0;
    //     const row = this.pricingElements[rowIndex];
    //     const previousDiscount = parseFloat(row.Discount_Amount__c) || 0;

    //     const priceMasterId = row['Pricing_Element_Master__c'];
    //     const selectedUnit = this.unitList.find(unit => unit.Id === this.selectedUnitId);
    //     if (priceMasterId) {
    //         for (let i = 0; i < this.discountLineItem.length; i++) {
    //             if (priceMasterId === this.discountLineItem[i].Discount_Master__r.Pricing_Element_Master__c) {
    //                 if (this.discountLineItem[i].Maximum__c < value) {
    //                     this.pricingElements[rowIndex]['limitExceed'] = "Discount Amount Limit exceeded " + this.discountLineItem[i].Maximum__c;
    //                     this.showToast('Error', 'Please Enter Discount Amount Less Than ' + this.discountLineItem[i].Maximum__c, 'error');
    //                     return;
    //                 } else {
    //                     row['limitExceed'] = "";
    //                 }
    //             }
    //         }
    //     }

    //     // Update the Discount_Amount__c in pricingElements
    //     if (fieldName === 'Discount_Amount__c' && (row.originalRate == null || row.originalRate === 0)) {
    //         row.originalRate = (parseFloat(row.Rate__c) || 0) + previousDiscount;
    //     }

    //     row[fieldName] = value;

    //     if (fieldName === 'Discount_Amount__c') {
    //         const originalRate = row.originalRate != null ? parseFloat(row.originalRate) : 0;
    //         const quantity = row.Quantity__c || 0;
    //         const originalAmount = originalRate * quantity;
    //         const taxAmount = row.permanantTax || 0;
    //         const originalTaxPercentage = (taxAmount / originalAmount) * 100 || 0; // Calculate the original tax percentage

    //         if (originalAmount > 0) {
    //             if (value > 0) {
    //                 // Discount is applied
    //                 const discountedRate = Math.max(originalRate - value, 0);
    //                 const discountedAmount = discountedRate * quantity;
    //                 const discountPercentage = (value / originalRate) * 100;
    //                 row.Discount__c = discountPercentage.toFixed(2);
    //                 row.Rate__c = discountedRate;
    //                 row.Amount__c = discountedAmount;
    //                 row.ActualAmount = discountedAmount;

    //                 // Recalculate tax based on the reduced amount
    //                 // const newTaxAmount = ((amount - value) * originalTaxPercentage) / 100;
    //                 // this.pricingElements[rowIndex].Tax_Amount__c = newTaxAmount.toFixed(2);
    //             } else {
    //                 // Discount is removed, reset to original values
    //                 row.Discount__c = 0;
    //                 row.Rate__c = originalRate;
    //                 row.Amount__c = originalAmount;
    //                 row.ActualAmount = originalAmount;

    //                 // Restore the original tax amount
    //                 // this.pricingElements[rowIndex].Tax_Amount__c = (amount * originalTaxPercentage) / 100;
    //             }
    //         }
    //     }

    //     this.syncRateWithAmount(row);

    //     // Calculate Total Tax Amount
    //     this.realAmount = this.pricingElements.reduce((sum, element) => {
    //         return sum + (parseFloat(element.ActualAmount) || 0);
    //     }, 0);

    //     console.log('this.taxAmount==>' + this.taxAmount);
    //     console.log('this.realAmount==>' + this.realAmount);
    //     this.formattedTotalAmount = this.realAmount + this.taxAmount;

    //     // const numericRealAmount = parseFloat(this.realAmount.replace(/[^0-9.]/g, ''));
    //     const numericRealAmount = parseFloat(String(this.realAmount).replace(/[^0-9.]/g, ''));
    //     const numericTaxAmount = parseFloat(String(this.taxAmount).replace(/[^0-9.]/g, ''));

    //     // Perform the calculation
    //     this.totalAmount = numericRealAmount + numericTaxAmount;

    //     // Optional: Format the result for display
    //     this.formattedTotalAmount = new Intl.NumberFormat('en-IN').format(this.totalAmount);
    //     // this.taxAmount = new Intl.NumberFormat('en-IN').format(this.taxAmount);
    //     // this.duplicatepricingElements = this.pricingElements;
    // }


    handleThirdScreen() {
        debugger;
        this.secondScreen = false;
        // this.thirdScreen = true;
        this.handleFouth();
    }

    handleFourthScreenBack() {
        debugger;
        this.secondScreen = true;
        this.thirdScreen = false;
    }

    handleParking(event) {
        debugger;
        this.getParkingDetails();
        this.parkingDetailTable = true;
    }

    @track parkingType = [];
    @track noParkingDetails = false;
    @track availableOpenParking = 0;
    @track availableDependantParking = 0;
    @track availableIndependantParking = 0;

    getParkingDetails() {
        debugger;
        getParkingRecords({ unitId: this.selectedUnitId })
            .then(result => {
                if (result && Array.isArray(result) && result.length > 0) {
                    this.parkingDetails = result;
                    this.parkingDetails.forEach(item => {
                        this.availableOpenParking = item.Parking_Type__c == 'Open' ? item.Available_Parking__c : this.availableOpenParking;
                        this.availableDependantParking = item.Parking_Type__c == 'Dependent' ? item.Available_Parking__c : this.availableDependantParking;
                        this.availableIndependantParking = item.Parking_Type__c == 'Independent' ? item.Available_Parking__c : this.availableIndependantParking;
                    });
                    this.parkingType = result.map(item => {
                        return { label: item.Parking_Type__c, value: item.Parking_Type__c }
                    });
                    this.noParkingDetails = false;
                    this.parkingDetailTable = true;
                } else {
                    this.noParkingDetails = true;
                    this.parkingDetailTable = false;
                }
            })
            .catch(error => {
                console.error('Error:', error);
                this.showToast('Error', 'Unable to fetch parking details.', 'error');
            });
    }

    handleParkingTypeChange(event) {
        debugger;
        const index = parseInt(event.target.dataset.index, 10);
        const id = event.target.dataset.id;
        const selectedType = event.target.value;
        const name = event.target.name;
        var parkingDetail = {};
        var quantity = 1;

        var currentRow = this.rows.find(item => item.id === id);
        console.log('currentRow ===> ' + currentRow);

        if (name == 'quantity') {
            quantity = selectedType;
            parkingDetail = this.parkingDetails.find(item => item.Parking_Type__c === currentRow.type);
            if (currentRow) {
                currentRow.quantity = quantity;
            }
        } else {
            parkingDetail = this.parkingDetails.find(
                item => item.Parking_Type__c === selectedType
            );
        }
        console.log('Updated Rows:', JSON.stringify(currentRow));

        var amount = parkingDetail != null ? parkingDetail.Amount__c : 0;
        var finalAmount = currentRow.quantity != '' && name != 'quantity' ? parkingDetail.Amount__c * currentRow.quantity : name == 'quantity' && selectedType != null ? parkingDetail.Amount__c * selectedType : 0;

        // const amount = parkingDetail ? (parkingDetail.Amount__c) : 0;
        `  console.log('Found Parking Detail:', parkingDetail);
            console.log('Amount for Selected Type:', amount);`


        // const previousAmount = this.rows[index]?.amount || 0;
        // this.totalAmount = this.totalAmount - previousAmount + finalAmount;

        // Format the totalAmount
        this.formattedTotalAmount = new Intl.NumberFormat('en-IN').format(this.totalAmount);
        this.rows = this.rows.map((row, rowIndex) => {
            if (rowIndex === index) {
                return {
                    ...row,
                    type: (name == 'quantity' && currentRow != null) ? currentRow.type : selectedType,
                    amount: amount,
                    quantity: currentRow['quantity'],
                    carCGSTtax: this.carParkingTax.CGST__c != null || this.carParkingTax.CGST__c != undefined ? this.carParkingTax.CGST__c : 0,
                    carSGSTtax: this.carParkingTax.SGST__c != null || this.carParkingTax.SGST__c != undefined ? this.carParkingTax.SGST__c : 0,
                    finalAmount: finalAmount,
                    taxAmt: (finalAmount * (parseFloat(this.carParkingTax?.CGST__c) / 100)) +
                        (finalAmount * (parseFloat(this.carParkingTax?.SGST__c) / 100)),
                    Parking_Numbers__c: ((name == 'quantity' || name == 'type') && currentRow != null) ? currentRow['Parking_Numbers__c'] : currentRow['Parking_Numbers__c'],
                };
            }
            return row;
        });

        this.updateAvailableOptions();
        console.log('Updated Rows:', this.rows);
        console.log('Updated Total Amount:', this.totalAmount);
        console.log('Formatted Total Amount:', this.formattedTotalAmount);

        const numericRealAmount = parseFloat(String(this.realAmount).replace(/[^0-9.]/g, ''));
        const numericTaxAmount = parseFloat(this.taxAmount);
        var finalAmountNew = this.rows.reduce((sum, element) => {
            return sum + (parseFloat(element.finalAmount) || 0);
        }, 0);
        this.totalAmount = numericRealAmount + numericTaxAmount + finalAmountNew;
        this.formattedTotalAmount = this.totalAmount;
    }


    updateAvailableOptions() {
        debugger;
        const selectedTypes = this.rows.map(row => row.type);

        const allOptions = [
            { label: 'Open', value: 'Open' },
            { label: 'Dependent', value: 'Dependent' },
            { label: 'Independent', value: 'Independent' },
        ];

        this.availableParkingTypes = allOptions.filter(
            option => !selectedTypes.includes(option.value)
        );
        console.log('this.availableParkingTypes==>' + this.availableParkingTypes);
    }

    handleAddRow() {
        debugger;
        const newRow = {
            id: `row_${Date.now()}`,
            type: '',
            quantity: 1,
            amount: '',
            carCGSTtax: this.carParkingTax.CGST__c != null || this.carParkingTax.CGST__c != undefined ? this.carParkingTax.CGST__c : 0,
            carSGSTtax: this.carParkingTax.SGST__c != null || this.carParkingTax.SGST__c != undefined ? this.carParkingTax.SGST__c : 0,
            taxAmt: '',
            finalAmount: '',
        };
        this.rows = [...this.rows, newRow];
    }

    handleDeleteRow(event) {
        debugger;
        const indexToDelete = parseInt(event.target.dataset.index, 10);
        console.log('Deleting row at index:', indexToDelete);

        const amountToSubtract = this.rows[indexToDelete]?.amount || 0;
        this.totalAmount -= amountToSubtract;
        this.formattedTotalAmount = new Intl.NumberFormat('en-IN').format(this.totalAmount);

        this.rows = this.rows.filter((_, rowIndex) => rowIndex !== indexToDelete);
        console.log('Updated rows:', this.rows);
        this.updateAvailableOptions();
    }

   // @track discountAdded = false;
   // @track discountByPricingMap = [];
    // handleFouth() {
    //     debugger;
    //     console.log('this.rows==>' + this.rows);

    //     if (this.rows && this.rows.length > 0) {
    //         this.isFourthNextDisabled = true;
    //         createparkingElements({ parkingElements: this.rows, costId: this.newCostSheetId })
    //             .then(result => {
    //                 console.log('Apex result:', result);
    //                 console.log('pricingElemets==>' + this.pricingElements);
    //                 this.pricingElements = this.pricingElements.filter(element =>
    //                     !element.parking_Element__c
    //                 );


    //                 this.pricingElements = [...this.pricingElements, ...result].map(item => ({
    //                     ...item,
    //                     ActualAmount: item.Amount__c
    //                 }));

    //                 console.log('Updated pricingElements:', this.pricingElements);

    //                 this.secondScreen = false;
    //                 this.fourthScreen = true;
    //                 this.isFourthNextDisabled = false;
    //             })
    //             .catch(error => {
    //                 console.error('Error during Apex call:', error);
    //                 this.isFourthNextDisabled = false;
    //             });
    //     } else {
    //         console.log('No parking element records to send.');
    //     }

    //     this.pricingElements = this.pricingElements.map(item => ({
    //         ...item,
    //         ActualAmount: item.Amount__c
    //     }));
    //     //this.discountAdded = this.pricingElements.some(item => item.Discount_Amount__c != null);

    //     // this.discountByPricingMap = [];
    //     // this.pricingElements.forEach(item => {
    //     //     if (item.Discount_Amount__c != null) {
    //     //         this.discountByPricingMap.push({
    //     //             discountAmount: item.Discount_Amount__c,
    //     //             id: item.Pricing_Element_Master__c
    //     //         });
    //     //     }
    //     // });
        
    //     this.thirdScreen = false;
    //     this.fourthScreen = true;
    // }

    handleFouth() {
        debugger;
        console.log('Parking rows:', JSON.stringify(this.rows));
        this.pricingElements = this.pricingElements.map(item => ({
            ...item,
            ActualAmount: item.Amount__c
        }));

        this.thirdScreen = false;
        this.fourthScreen = true;
    }

    handleBack() {
        debugger;
        this.thirdScreen = false;
        this.fourthScreen = false;
        this.secondScreen = true;
    }

    // handleFinalSave() {
    //     debugger;
    //     console.log('this.costSheetId' + this.newCostSheetId);
    //     console.log('Pricing Elements to update:', JSON.stringify(this.pricingElements));
    //     this.isFianlSaveDisabled = true;
    //     this.discountAdded = true;
    //     console.log('this.discountAdded' + this.discountAdded);
    //     updatePricingElements({ pricingElements: this.getPricingElementsForSave() })
    //         .then(result => {
    //             //if (this.discountAdded == true) {
    //                // console.log('this.discountAdded ==> ', this.discountAdded);
    //                 console.log('submit for approval');
    //                 this.submitForApproval();
    //             //}
    //             console.log('Upsert successful:', result);
    //             this.showToast('Success', 'Pricing Elements are Updated Successfully..', 'success');
    //             this.isFianlSaveDisabled = false;
    //             this.closeAction();
    //             this.closeComponent();
    //         })
    //         .catch(error => {
    //             console.error('Error during upsert:', error);
    //             this.isFianlSaveDisabled = false;
    //         });
    // }
    handleFinalSave() {
        debugger;
        this.isFianlSaveDisabled = true;
        const pricingElements = this.getPricingElementsForSave();
        console.log('Pricing Elements:',JSON.stringify(pricingElements));
        console.log( 'Parking Elements:',JSON.stringify(this.rows));
        console.log('Discount Amount:', this.discountAmount);
        console.log( 'Discount Percentage:',this.discountPercent);
        saveCostSheet({
            opp: this.opp,
            tasks: this.opp.Tasks,
            unitId: this.selectedUnitId,
            cslId: this.selectedCostSchemeId,
            pricingElements: pricingElements,
            parkingElements: this.rows,
            discountAmount: this.discountApplicable === 'Yes' ? parseFloat(this.discountAmount) || 0 : 0,
            discountPercent:
                this.discountApplicable === 'Yes'
                    ? parseFloat(this.discountPercent) || 0
                    : 0
        })
        .then(costSheetId => {
            this.newCostSheetId = costSheetId;
            console.log('Cost Sheet Created:',this.newCostSheetId);
            console.log('Calling submitForApproval...');
            this.submitForApproval();

            this.showToast(
                'Success',
                'Cost Sheet and Pricing Elements saved successfully.',
                'success'
            );
            this.isFianlSaveDisabled = false;
            this.closeAction();
            this.closeComponent();
        })
        .catch(error => {
            console.error( 'Error while saving Cost Sheet:', error);
            console.error('Error body:',error?.body?.message);
            this.showToast(
                'Error',
                error?.body?.message ||
                'Error while saving Cost Sheet.',
                'error'
            );
            this.isFianlSaveDisabled = false;
        });
    }

    submitForApproval() {
        debugger;
        console.log('Cost Sheet Id:', this.newCostSheetId);
        submitCostSheetForApproval({ data: null, costSheetId: this.newCostSheetId })//JSON.stringify(this.discountByPricingMap)
            .then(result => {
                console.log('Apex call success', result);
            })
            .catch(error => {
                console.error('Apex call failed', error);
            });

    }

    getPricingElementsForSave() {
        return this.pricingElements.map(item => ({
            Id: item.Id,
            Cost_Sheet__c: item.Cost_Sheet__c,
            Pricing_Element_Master__c: item.Pricing_Element_Master__c,
            PE_Type__c: item.PE_Type__c,
            Quantity__c: item.Quantity__c,
            Rate__c: this.getRateForSave(item),
            Unit__c: item.Unit__c,
            Type__c: item.Type__c,
            Amount__c: item.Amount__c,
            Discount_Amount__c: item.Discount_Amount__c,
            Discount__c: item.Discount__c,
            SGST_Tax_Percentage__c: item.SGST_Tax_Percentage__c,
            CGST_Tax_Percentage__c: item.CGST_Tax_Percentage__c,
            IGST_Tax_Percentage__c: item.IGST_Tax_Percentage__c,
            parking_Element__c: item.parking_Element__c
        }));
    }

    getRateForSave(item) {
        const quantity = parseFloat(item.Quantity__c) || 0;
        const amount = parseFloat(item.Amount__c) || 0;

        if (quantity > 0 && amount > 0) {
            return amount / quantity;
        }

        return item.Rate__c;
    }

    syncRateWithAmount(item) {
        const quantity = parseFloat(item.Quantity__c) || 0;
        const amount = parseFloat(item.Amount__c) || 0;

        if (quantity > 0 && amount > 0) {
            item.Rate__c = amount / quantity;
        }
    }

    showToast(title, message, variant) {
        debugger;
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
        });
        this.dispatchEvent(event);
    }

    closeAction() {
        debugger;
        this.dispatchEvent(new CloseActionScreenEvent());
        this.closeModal();
    }

    closeModal() {
        debugger;
        // Dispatch a custom event to notify parent to close the modal
        const closeEvent = new CustomEvent('cancel');
        this.dispatchEvent(closeEvent);
    }

    closeComponent() {
        debugger;
        // Dispatch an event called "close"
        const closeEvent = new CustomEvent('close');
        this.dispatchEvent(closeEvent);
    }
}