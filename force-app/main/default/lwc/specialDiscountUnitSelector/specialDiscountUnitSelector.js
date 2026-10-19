import { LightningElement, api } from 'lwc';

import getInitialData
    from '@salesforce/apex/SpecialDiscountUnitController.getInitialData';

import getFloors
    from '@salesforce/apex/SpecialDiscountUnitController.getFloors';

import getUnits
    from '@salesforce/apex/SpecialDiscountUnitController.getUnits';

import saveUnits
    from '@salesforce/apex/SpecialDiscountUnitController.saveUnits';

import { ShowToastEvent }
    from 'lightning/platformShowToastEvent';


const COLUMNS = [
    {
        label: 'Unit',
        fieldName: 'unitCode'
    },
    {
        label: 'Tower',
        fieldName: 'blockName'
    },
    {
        label: 'Floor',
        fieldName: 'floorName'
    },
    {
        label: 'Unit Type',
        fieldName: 'unitType'
    },
    {
        label: 'Status',
        fieldName: 'status'
    }
];


export default class SpecialDiscountUnitSelector
    extends LightningElement {

    @api recordId;


    // =====================================================
    // TABLE
    // =====================================================

    columns = COLUMNS;

    units = [];

    totalCount = 0;


    // =====================================================
    // FILTER OPTIONS
    // =====================================================

    blockOptions = [
        {
            label: 'All Towers',
            value: 'ALL'
        }
    ];

    floorOptions = [
        {
            label: 'All Floors',
            value: 'ALL'
        }
    ];

    unitTypeOptions = [
        {
            label: 'All Unit Types',
            value: 'ALL'
        }
    ];


    // =====================================================
    // FILTER VALUES
    // =====================================================

    selectedBlock = 'ALL';

    selectedFloor = 'ALL';

    selectedUnitType = 'ALL';

    searchTerm = '';


    // =====================================================
    // PAGINATION
    // =====================================================

    pageNumber = 1;

    pageSize = 50;

    hasNext = false;

    hasPrevious = false;


    // =====================================================
    // SELECTION
    // =====================================================

    selectedUnitIds = new Set();


    // =====================================================
    // STATE
    // =====================================================

    loading = false;

    searchTimer;


    // =====================================================
    // COMPONENT INITIALIZATION
    // =====================================================

    connectedCallback() {

        this.initializeComponent();

    }


    async initializeComponent() {

        this.loading = true;

        try {

            const result = await getInitialData({
                specialDiscountId: this.recordId
            });


            this.blockOptions =
                result?.blockOptions || [
                    {
                        label: 'All Towers',
                        value: 'ALL'
                    }
                ];


            this.floorOptions =
                result?.floorOptions || [
                    {
                        label: 'All Floors',
                        value: 'ALL'
                    }
                ];


            this.unitTypeOptions =
                result?.unitTypeOptions || [
                    {
                        label: 'All Unit Types',
                        value: 'ALL'
                    }
                ];


            await this.loadUnits();

        } catch (error) {

            this.showToast(
                'Error loading unit selector',
                this.getErrorMessage(error),
                'error'
            );

        } finally {

            this.loading = false;

        }

    }


    // =====================================================
    // LOAD UNITS
    // =====================================================

    async loadUnits() {

        this.loading = true;

        try {

            const result = await getUnits({

                specialDiscountId:
                    this.recordId,

                blockId:
                    this.selectedBlock === 'ALL'
                        ? null
                        : this.selectedBlock,

                floorId:
                    this.selectedFloor === 'ALL'
                        ? null
                        : this.selectedFloor,

                unitType:
                    this.selectedUnitType,

                searchTerm:
                    this.searchTerm,

                pageNumber:
                    this.pageNumber,

                pageSize:
                    this.pageSize

            });


            this.units =
                result?.units || [];


            this.totalCount =
                result?.totalCount || 0;


            this.pageNumber =
                result?.pageNumber || 1;


            this.pageSize =
                result?.pageSize || 50;


            this.hasNext =
                result?.hasNext || false;


            this.hasPrevious =
                result?.hasPrevious || false;


        } catch (error) {

            this.units = [];

            this.totalCount = 0;

            this.showToast(
                'Error loading units',
                this.getErrorMessage(error),
                'error'
            );

        } finally {

            this.loading = false;

        }

    }


    // =====================================================
    // TOWER CHANGE
    // =====================================================

    async handleBlockChange(event) {

        this.selectedBlock =
            event.detail.value;


        this.selectedFloor =
            'ALL';


        this.pageNumber =
            1;


        if (this.selectedBlock === 'ALL') {

            // Reload all project floors

            try {

                const result =
                    await getInitialData({
                        specialDiscountId:
                            this.recordId
                    });


                this.floorOptions =
                    result?.floorOptions || [
                        {
                            label: 'All Floors',
                            value: 'ALL'
                        }
                    ];

            } catch (error) {

                this.showToast(
                    'Error loading floors',
                    this.getErrorMessage(error),
                    'error'
                );

            }

        } else {

            try {

                this.floorOptions =
                    await getFloors({

                        specialDiscountId:
                            this.recordId,

                        blockId:
                            this.selectedBlock

                    });

            } catch (error) {

                this.showToast(
                    'Error loading floors',
                    this.getErrorMessage(error),
                    'error'
                );

                return;

            }

        }


        await this.loadUnits();

    }


    // =====================================================
    // FLOOR CHANGE
    // =====================================================

    async handleFloorChange(event) {

        this.selectedFloor =
            event.detail.value;


        this.pageNumber =
            1;


        await this.loadUnits();

    }


    // =====================================================
    // UNIT TYPE CHANGE
    // =====================================================

    async handleUnitTypeChange(event) {

        this.selectedUnitType =
            event.detail.value;


        this.pageNumber =
            1;


        await this.loadUnits();

    }


    // =====================================================
    // SEARCH
    // =====================================================

    handleSearch(event) {

        this.searchTerm =
            event.target.value || '';


        this.pageNumber =
            1;


        clearTimeout(
            this.searchTimer
        );


        this.searchTimer =
            setTimeout(() => {

                this.loadUnits();

            }, 400);

    }


    // =====================================================
    // ROW SELECTION
    // =====================================================

    handleRowSelection(event) {

        const currentPageIds =
            new Set(
                this.units.map(
                    unit => unit.unitId
                )
            );


        // Remove previous selection belonging
        // to current page only.

        currentPageIds.forEach(id => {

            this.selectedUnitIds.delete(id);

        });


        // Add currently selected rows.

        event.detail.selectedRows.forEach(
            row => {

                this.selectedUnitIds.add(
                    row.unitId
                );

            }
        );


        // Force reactivity

        this.selectedUnitIds =
            new Set(
                this.selectedUnitIds
            );

    }


    // =====================================================
    // PREVIOUS PAGE
    // =====================================================

    async handlePrevious() {

        if (!this.hasPrevious) {
            return;
        }


        this.pageNumber--;


        await this.loadUnits();

    }


    // =====================================================
    // NEXT PAGE
    // =====================================================

    async handleNext() {

        if (!this.hasNext) {
            return;
        }


        this.pageNumber++;


        await this.loadUnits();

    }


    // =====================================================
    // SAVE
    // =====================================================

    async handleSave() {

        if (
            this.selectedUnitIds.size === 0
        ) {

            this.showToast(
                'No Units Selected',
                'Please select at least one Unit.',
                'warning'
            );

            return;

        }


        this.loading = true;


        try {

            const count =
                await saveUnits({

                    specialDiscountId:
                        this.recordId,

                    unitIds:
                        Array.from(
                            this.selectedUnitIds
                        )

                });


            this.showToast(
                'Units Added',
                `${count} Unit(s) added successfully.`,
                'success'
            );


            // Clear selection because saved Units
            // disappear from Available Units.

            this.selectedUnitIds =
                new Set();


            this.pageNumber =
                1;


            await this.loadUnits();


        } catch (error) {

            this.showToast(
                'Unable to Save Units',
                this.getErrorMessage(error),
                'error'
            );

        } finally {

            this.loading = false;

        }

    }


    // =====================================================
    // GETTERS
    // =====================================================

    get selectedRows() {

        return Array.from(
            this.selectedUnitIds
        );

    }


    get selectedCount() {

        return this.selectedUnitIds.size;

    }


    get totalPages() {

        if (
            !this.totalCount ||
            !this.pageSize
        ) {

            return 1;

        }


        return Math.ceil(
            this.totalCount /
            this.pageSize
        );

    }


    get disablePrevious() {

        return (
            !this.hasPrevious ||
            this.loading
        );

    }


    get disableNext() {

        return (
            !this.hasNext ||
            this.loading
        );

    }


    get disableSave() {

        return (
            this.selectedUnitIds.size === 0 ||
            this.loading
        );

    }


    // =====================================================
    // TOAST
    // =====================================================

    showToast(
        title,
        message,
        variant
    ) {

        this.dispatchEvent(

            new ShowToastEvent({

                title,
                message,
                variant

            })

        );

    }


    // =====================================================
    // ERROR HANDLER
    // =====================================================

    getErrorMessage(error) {

        if (
            error?.body?.message
        ) {

            return error.body.message;

        }


        if (
            Array.isArray(
                error?.body
            )
        ) {

            return error.body
                .map(
                    item =>
                        item.message
                )
                .join(', ');

        }


        return (
            error?.message ||
            'Unexpected error occurred.'
        );

    }

}