import { LightningElement, api, track } from 'lwc';

const chunk = (arr, size) => {
    const chunkedArray = [];
    for (let i = 0; i < arr.length; i++) {
        const last = chunkedArray[chunkedArray.length - 1];
        if (!last || last.length === size) {
            chunkedArray.push([arr[i]]);
        } else {
            last.push(arr[i]);
        }
    };
    return chunkedArray;
};

export default class CustomPaginationComp extends LightningElement {
    @api list;
    currentPage = "1";
    @api contactChunks;
    contactToDisplay;
    totalPages;
    disableNext = false;
    disablePrev = true;
    pageOptionsLoaded = false;
    @track pageOptions = [];
    size;
    totalRecords=0;
    pageLimit = "10";
    @track pageParam;

    get pageLimitOptions() {
        debugger;
        var pageLimitList = [
            { label: '5', value: '5' },
            { label: '10', value: '10' },
            { label: '15', value: '15' },
            { label: '20', value: '20' },
            { label: '50', value: '50' },
            { label: '100', value: '100' },
        ];
        return pageLimitList;
    }

    @api
    setPagination(size) {
        debugger;
        console.log('this.list==>' + JSON.stringify(this.list));
        console.log('length' + this.list.length);
        if (!this.list || this.list.length === 0) {
               console.log("No data available for pagination.");
                        this.contactChunks = [];
                         this.contactToDisplay = [];
                         this.pageOptions = [];
                         this.totalPages = 0;
                         this.pageOptionsLoaded = false;
                         this.totalRecords=0;
                         this.calculatePageText();
            return;
         }

        if (this.list.length > 0) {
            debugger;
            this.pageOptions = [];
            this.disableNext = this.list.length <= size// false;
            this.disablePrev = true;
            this.size = size;
            this.currentPage = "1";
            this.totalRecords = this.list.length;
            this.contactChunks = chunk(this.list, this.size);
            this.contactToDisplay = this.contactChunks[0];
            this.totalPages = this.contactChunks.length;

            var pageOptObj = {};
            for (var i = 1; i <= this.totalPages; i++) {
                pageOptObj = {};
                pageOptObj.label = i.toString();
                pageOptObj.value = i.toString();
                this.pageOptions.push(pageOptObj);
            }
            console.log("ListLenght---", this.list.length);
            console.log("Size---", this.size);

            debugger;
            if (this.list.length == this.size) {
                this.pageOptions.slice(0, -1);
                console.log("pageOptions-----", this.pageOptions);
            }
            this.pageOptionsLoaded = true;
            this.calculatePageText();
        }
        
        
    }

    calculatePageText() {
        debugger;
        var end = (parseInt(this.currentPage) * this.size) > this.totalRecords ? this.totalRecords : (parseInt(this.currentPage) * this.size);
        this.pageParam = ((parseInt(this.currentPage) * this.size) - (this.size - 1)) + ' to ' + end;
        this.pageParam=this.pageParam.includes('NaN')?'0 to 0':this.pageParam;
        console.log('this.pageParam ===> ' + this.pageParam);
        console.log('this.totalRecords ===> ' + this.totalRecords);
        this.returnRecordToDisplay();
    }

    handleNext() {
        debugger;
        this.currentPage = (parseInt(this.currentPage) + 1).toString();

        if (parseInt(this.currentPage) >= this.totalPages) {
            this.currentPage = this.totalPages.toString();
            this.disableNext = true;
            this.disablePrev = false;
        }
        else {
            this.disableNext = false;
            this.disablePrev = false;
        }

        this.contactToDisplay = this.contactChunks[parseInt(this.currentPage) - 1];
        this.calculatePageText();
    }

    handlePrev() {
        debugger;
        this.currentPage = (parseInt(this.currentPage) - 1).toString();

        if (parseInt(this.currentPage) <= "1") {
            this.currentPage = "1";
            this.disableNext = false;
            this.disablePrev = true;
        }
        else {
            this.disableNext = false;
            this.disablePrev = false;
        }

        this.contactToDisplay = this.contactChunks[parseInt(this.currentPage) - 1];
        this.calculatePageText();
    }

    handlePageChange(event) {
        debugger;
        this.currentPage = event.target.value;
        this.contactToDisplay = this.contactChunks[parseInt(this.currentPage) - 1];
        if (parseInt(this.currentPage) <= "1") {
            this.disableNext = false;
            this.disablePrev = true;
        }
        else if (parseInt(this.currentPage) >= this.totalPages) {
            this.disableNext = true;
            this.disablePrev = false;
        }
        else {
            this.disableNext = false;
            this.disablePrev = false;
        }
        this.calculatePageText();
    }

    handleFirst() {
        debugger;
        this.currentPage = "1";
        this.disableNext = false;
        this.disablePrev = true;
        this.contactToDisplay = this.contactChunks[parseInt(this.currentPage) - 1];
        this.calculatePageText();
    }

    handleLast() {
        debugger;
        this.currentPage = this.totalPages.toString();
        this.disableNext = true;
        this.disablePrev = false;
        this.contactToDisplay = this.contactChunks[parseInt(this.currentPage) - 1];
        this.calculatePageText();
    }

    handleLimitChange(event) {
        debugger;
        this.pageLimit = event.detail.value;
        this.selectedPage = '1';
        this.size = parseInt(this.pageLimit)
        this.setPagination(this.size); //invoking the pagination logic
        //this.calculatePageText();
    }

    returnRecordToDisplay() {
        debugger;
        let event = new CustomEvent('pagechanged', { detail: { recordToDisplay: this.contactToDisplay,curPage:this.currentPage } });
        this.dispatchEvent(event);
    }
}