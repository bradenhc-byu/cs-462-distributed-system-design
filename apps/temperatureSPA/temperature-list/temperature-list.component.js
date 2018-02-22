// Define the temperature component
angular.module('temperatureList').component('temperatureList', {
	templateUrl: 'temperature-list/temperature-list.component.html',
	controller: ['$http', '$interval', function TemperatureListController($http, $interval) {
		this.eci = "KKCc3MKtp13YPBbFjvhscR";
		this.temperatures = [];

		// These are the API URLs we need for this component
		var _this = this;
		var host = "http://localhost:8080/";
		var url = host + "sky/cloud/"+this.eci+"/temperature_store/temperatures";

		// Setup an interval function
		var liveTemperatures;
		this.getLiveTemperatures = function(){
				$http.get(url).then(
					function success(response){
						_this.temperatures = [];
						for(var k in response.data){
							_this.temperatures.push({timestamp: k, temperature: response.data[k]})
							if(_this.temperatures.length == 4) break;
						}
					},
					function error(response){
						_this.temperatures.push({timestamp: "Fail", temperature: "Fail"})
				});		
		};

		liveTemperatures = $interval(this.getLiveTemperatures, 1000);

		this.$onDestroy = function(){
			if(angular.isDefined(liveTemperatures)){
				$interval.cancel(liveTemperatures);
				liveTemperatures = undefined;
			}
		};
	}]
});