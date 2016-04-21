{#

OPNsense® is Copyright © 2016 by Deciso B.V.
All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

1.  Redistributions of source code must retain the above copyright notice,
this list of conditions and the following disclaimer.

2.  Redistributions in binary form must reproduce the above copyright notice,
this list of conditions and the following disclaimer in the documentation
and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED “AS IS” AND ANY EXPRESS OR IMPLIED WARRANTIES,
INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY,
OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.

#}

<style type="text/css">
.panel-heading-sm{
    height: 28px;
    padding: 4px 10px;
}
</style>

<!-- nvd3 -->
<link rel="stylesheet" href="/ui/css/nv.d3.css">

<!-- d3 -->
<script type="text/javascript" src="/ui/js/d3.min.js"></script>

<!-- nvd3 -->
<script type="text/javascript" src="/ui/js/nv.d3.min.js"></script>

<script type="text/javascript">
    $( document ).ready(function() {
      var resizeEnd ;
      $(window).on('resize', function() {
          clearTimeout(resizeEnd);
          resizeEnd = setTimeout(function() {
              $(window).trigger('resize-end');
          }, 500);
      });

      // collect all chars for resize update
      var pageCharts = {};

      // form metadata definitions
      var interface_names = [];
      var service_names = [];
      var protocol_names = [];

      /**
       * load shared metadata (interfaces, protocols, )
       */
      function get_metadata()
      {
          var dfObj = new $.Deferred();
          // fetch interface names
          ajaxGet('/api/diagnostics/networkinsight/getInterfaces',{},function(intf_names,status){
              interface_names = intf_names;
              // fetch protocol names
              ajaxGet('/api/diagnostics/networkinsight/getProtocols',{}, function(protocols, status) {
                  protocol_names = protocols;
                  // fetch service names
                  ajaxGet('/api/diagnostics/networkinsight/getServices',{}, function(services, status) {
                      service_names = services;
                      dfObj.resolve();
                  });
              });
          });
          return dfObj;
      }

      /**
       * delete all graps accounted in pageCharts
       */
      function delete_all_charts()
      {
          var svg = d3.select("svg");
          svg.selectAll("*").remove();
          pageCharts = {};
      }

      /**
       * get selected time
       */
      function get_time_select()
      {
          // current time stamp
          var timestamp_now = Math.round((new Date()).getTime() / 1000);
          var duration = 0;
          var resolution = 0;
          switch ($("#total_time_select").val()) {
              case "2h":
                duration = 60*60*2;
                resolution = 30;
                break;
              case "8h":
                duration = 60*60*8;
                resolution = 300;
                break;
              case "1w":
                duration = 60*60*24*7;
                resolution = 3600;
                break;
              case "1m":
                duration = 60*60*24*31;
                resolution = 86400;
                break;
              case "1y":
                duration = 60*60*24*365;
                resolution = 86400;
                break;
          }
          // always round from timestamp to nearest hour
          from_timestamp =  Math.floor((timestamp_now -duration) / 3600 ) * 3600;
          return {resolution: resolution, from: from_timestamp, to: timestamp_now};
      }

      /**
       * draw interface totals
       */
      function chart_interface_totals() {
        var selected_time = get_time_select();
        fetch_params = selected_time.from + '/' + selected_time.to + '/' + selected_time.resolution + '/if,direction' ;
        ajaxGet('/api/diagnostics/networkinsight/timeserie/FlowInterfaceTotals/bps/' + fetch_params,{},function(data,status){
            $.each(['chart_intf_in', 'chart_intf_out'], function(idx, target) {
                var direction = '';
                if (target == 'chart_intf_in') {
                    direction = 'in';
                } else {
                    direction = 'out';
                }
                nv.addGraph(function() {
                  var chart = nv.models.stackedAreaChart()
                      .x(function(d) { return d[0] })
                      .y(function(d) { return d[1] })
                      .useInteractiveGuideline(true)
                      .interactive(true)
                      .showControls(true)
                      .clipEdge(true);

                  if (selected_time.resolution < 60) {
                      chart.xAxis.tickSize(8).tickFormat(function(d) {
                        return d3.time.format('%b %e %H:%M:%S')(new Date(d));
                      });
                  } else if (selected_time.resolution < 3600) {
                      chart.xAxis.tickSize(8).tickFormat(function(d) {
                        return d3.time.format('%b %e %H:%M')(new Date(d));
                      });
                  } else if (selected_time.resolution < 86400) {
                      chart.xAxis.tickSize(8).tickFormat(function(d) {
                        return d3.time.format('%b %e %H h')(new Date(d));
                      });
                  } else {
                      chart.xAxis.tickFormat(function(d) {
                        return d3.time.format('%b %e')(new Date(d));
                      });
                  }
                  chart.yAxis.tickFormat(d3.format(',.2s'));

                  chart_data = [];
                  data.map(function(item){
                      item_dir = item.key.split(',').pop();
                      item_intf = item.key.split(',')[0];
                      if (item_intf != '0' && item_intf != 'lo0' ) {
                          if (direction == item_dir) {
                              if (interface_names[item_intf] != undefined) {
                                  item.key = interface_names[item_intf];
                              } else {
                                  item.key = item_intf;
                              }
                              chart_data.push(item);
                          }
                      }
                  });

                  chart_data.sort(function(a, b) {
                      return a.key > b.key;
                  });

                  d3.select("#" + target + " svg").datum(chart_data).call(chart);

                  pageCharts[target] = chart;
                  return chart;
                });
              });
          });
      }

      /**
       * graph top usage per destination port for selected time period
       */
      function chart_top_dst_port_usage()
      {
        // remove existing chart
        if (pageCharts["chart_top_ports"] != undefined) {
            var svg = d3.select("#chart_top_ports > svg");
            svg.selectAll("*").remove();
        }
        var selected_time = get_time_select();
        var time_url = selected_time.from + '/' + selected_time.to;
        ajaxGet('/api/diagnostics/networkinsight/top/FlowDstPortTotals/'+time_url+'/dst_port,protocol/octets/25/',
            {'filter_field': 'if', 'filter_value': $('#interface_select').val()}, function(data, status){
            if (status == 'success'){
              nv.addGraph(function() {
                var chart = nv.models.pieChart()
                    .x(function(d) { return d.label })
                    .y(function(d) { return d.value })
                    .showLabels(true)
                    .labelThreshold(.05)
                    .labelType("percent")
                    .donut(true)
                    .donutRatio(0.35)
                    .legendPosition("right")
                    .valueFormat(d3.format(',.2s'));
                    ;

                  chart_data = [];
                  data.map(function(item){
                      var label = "(other)";
                      var proto = "";
                      if (item.protocol != "") {
                          if (item.protocol in protocol_names) {
                              proto = ' (' + protocol_names[item.protocol] + ')';
                          }
                          if (item.dst_port in service_names) {
                              label = service_names[item.dst_port];
                          } else {
                              label = item.dst_port
                          }
                      }
                      chart_data.push({'label': label + proto, 'value': item.total});
                  });

                  d3.select("#chart_top_ports svg")
                      .datum(chart_data)
                      .transition().duration(350)
                      .call(chart);
                pageCharts["chart_top_ports"] = chart;

                // copy selection to detail page and query results
                chart.pie.dispatch.on('elementClick', function(e){
                    if (data[e.index].dst_port != "") {
                        $("#interface_select_detail").val($("#interface_select").val());
                        $('#interface_select_detail').selectpicker('refresh');
                        $("#service_port_detail").val(data[e.index].dst_port);
                        $("#address_detail").val("");
                        $("#details_tab").click();
                        grid_details();
                    }
                });

                return chart;
              });
            }
        });
      }

      /**
       * graph top usage per destination port for selected time period
       */
      function chart_top_src_addr_usage()
      {
        // remove existing chart
        if (pageCharts["chart_top_sources"] != undefined) {
            var svg = d3.select("#chart_top_sources > svg");
            svg.selectAll("*").remove();
        }
        var selected_time = get_time_select();
        var time_url = selected_time.from + '/' + selected_time.to;
        ajaxGet('/api/diagnostics/networkinsight/top/FlowSourceAddrTotals/'+time_url+'/src_addr/octets/25/',
            {'filter_field': 'if', 'filter_value': $('#interface_select').val()}, function(data, status){
            if (status == 'success'){
              nv.addGraph(function() {
                var chart = nv.models.pieChart()
                    .x(function(d) { return d.label })
                    .y(function(d) { return d.value })
                    .showLabels(true)
                    .labelThreshold(.05)
                    .labelType("percent")
                    .donut(true)
                    .donutRatio(0.35)
                    .legendPosition("right")
                    .valueFormat(d3.format(',.2s'));

                  chart_data = [];
                  data.map(function(item){
                      var label = "(other)";
                      if (item.src_addr != "") {
                          label = item.src_addr;
                      }
                      chart_data.push({'label': label, 'value': item.total});
                  });

                  d3.select("#chart_top_sources svg")
                      .datum(chart_data)
                      .transition().duration(350)
                      .call(chart);
                pageCharts["chart_top_sources"] = chart;

                // copy selection to detail tab and query results
                chart.pie.dispatch.on('elementClick', function(e){
                    if (data[e.index].src_addr != "") {
                        $("#interface_select_detail").val($("#interface_select").val());
                        $('#interface_select_detail').selectpicker('refresh');
                        $("#service_port_detail").val("");
                        $("#address_detail").val(data[e.index].src_addr);
                        $("#details_tab").click();
                        grid_details();
                    }
                });
                return chart;
              });
            }
        });
      }

      /**
       * collect netflow details
       */
      function grid_details()
      {
        var filters = {'filter_field': [], 'filter_value': []};
        if ($("#interface_select_detail").val() != "") {
            filters['filter_field'].push('if');
            filters['filter_value'].push($("#interface_select_detail").val());
        }
        if ($("#service_port_detail").val() != "") {
            filters['filter_field'].push('service_port');
            filters['filter_value'].push($("#service_port_detail").val());
        }
        if ($("#address_detail").val() != "") {
            filters['filter_field'].push('src_addr');
            filters['filter_value'].push($("#address_detail").val());
        }

        var time_url = $("#date_detail_from").val() + '/' +  $("#date_detail_to").val();
        ajaxGet('/api/diagnostics/networkinsight/top/FlowSourceAddrDetails/'+time_url+'/service_port,protocol,if,src_addr,dst_addr/octets/100/',
            {'filter_field': filters['filter_field'].join(','), 'filter_value': filters['filter_value'].join(',')}, function(data, status){
            if (status == 'success'){
                var html = []
                // count total traffic
                grand_total = 0;
                data.map(function(item){
                    grand_total += item['total'];
                });
                // dump  rows
                data.map(function(item){
                  if (item.protocol in protocol_names) {
                      proto = ' (' + protocol_names[item.protocol] + ')';
                  } else {
                      proto = ''
                  }
                  if (item.service_port in service_names) {
                      service_port = service_names[item.service_port];
                  } else {
                      service_port = item.service_port
                  }
                  tr_str = '<tr>';
                  if (service_port != "") {
                      tr_str += '<td> <span data-toggle="tooltip" title="'+proto+'/'+item.service_port+'">'+service_port+' </span> '+proto+'</td>';
                  } else {
                      tr_str += "<td>{{ lang._('(other)') }}</td>";
                  }
                  tr_str += '<td>' + item['src_addr'] + '</td>';
                  tr_str += '<td>' + item['dst_addr'] + '</td>';
                  tr_str += '<td>' + byteFormat(item['total']) + ' ' + '</td>';
                  if (item['last_seen'] != "") {
                      tr_str += '<td>' + d3.time.format('%b %e %H:%M:%S')(new Date(item['last_seen']*1000)) + '</td>';
                  } else {
                      tr_str += '<td></td>'
                  }


                  percentage = parseInt((item['total'] /grand_total) * 100);
                  perc_text = ((item['total'] /grand_total) * 100).toFixed(2);
                  tr_str += '<td>';
                  tr_str += '<div class="progress">';
                  tr_str += '<div class="progress-bar progress-bar-info progress-bar-striped" role="progressbar" ';
                  tr_str += 'aria-valuenow="'+percentage+'" aria-valuemin="0" aria-valuemax="100" style="min-width: 2em; width:' ;
                  tr_str += percentage+'%;">'+perc_text+'%</div></div>';
                  tr_str += '</td>';
                  tr_str += '</tr>';
                  html.push(tr_str);
                });
                $("#netflow_details > tbody").html(html.join(''));
                if (grand_total > 0) {
                    $("#netflow_details_total").html(byteFormat(grand_total));
                } else {
                    $("#netflow_details_total").html("");
                }

                // link tooltips
                $('[data-toggle="tooltip"]').tooltip();
            }
        });
      }

      // hide heading
      $(".page-content-head").addClass("hidden");

      // event page resize
      $(window).on('resize-end', function() {
          $.each(pageCharts, function(idx, chart) {
            chart.update();
          });
      });

      // event change time select
      $("#total_time_select").change(function(){
          delete_all_charts();
          chart_interface_totals();
          chart_top_dst_port_usage();
          chart_top_src_addr_usage();
      });

      // event change interface selection
      $('#interface_select').change(function(){
          chart_top_dst_port_usage();
          chart_top_src_addr_usage();
      });

      $('a[data-toggle="tab"]').on('shown.bs.tab', function (e) {
          // load charts for selected tab
          if (e.target.id == 'totals_tab'){
              $("#total_time_select").change();
          } else if (e.target.id == 'details_tab'){
          }
      });
      // detail page, search on <enter>
      $("#service_port_detail").keypress(function (e) {
          if (e.which == 13) {
              grid_details();
          }
      });
      $("#address_detail").keypress(function (e) {
          if (e.which == 13) {
              grid_details();
          }
      });


      // trigger initial tab load
      get_metadata().done(function(){
          // known interfaces
          for (var key in interface_names) {
              $('#interface_select').append($("<option></option>").attr("value",key).text(interface_names[key]));
              $('#interface_select_detail').append($("<option></option>").attr("value",key).text(interface_names[key]));
          }
          $('#interface_select').selectpicker('refresh');
          $('#interface_select_detail').selectpicker('refresh');

          // generate date selection (utc start, end times)
          var now = new Date;
          var date_begin = Date.UTC(now.getUTCFullYear(),now.getUTCMonth(), now.getUTCDate(), 0, 0, 0, 0);
          var date_end  = Date.UTC(now.getUTCFullYear(),now.getUTCMonth(), now.getUTCDate(), 23, 59, 59, 0);
          var tmp_date = new Date();
          for (i=0; i < 62; i++) {
              from_date_ts = (date_begin - (24*60*60*1000 * i)) / 1000;
              to_date_ts = parseInt((date_end - (24*60*60*1000 * i)) / 1000);
              tmp_date = new Date(from_date_ts*1000);
              tmp = tmp_date.getDate() + '/' + (tmp_date.getMonth()+1) + '/' + tmp_date.getFullYear();
              $("#date_detail_from").append($("<option/>").val(from_date_ts).text(tmp));
              $("#date_detail_to").append($("<option/>").val(to_date_ts).text(tmp));
          }

          $("#date_detail_from").selectpicker('refresh');
          $("#date_detail_to").selectpicker('refresh');
          $("#date_detail_from").change(function(){
              // change to date on change from date.
              $("#date_detail_to").prop('selectedIndex', $("#date_detail_from").prop('selectedIndex'));
              $("#date_detail_to").selectpicker('refresh');
          });

          chart_interface_totals();
          chart_top_dst_port_usage();
          chart_top_src_addr_usage();
      });


      $("#refresh_details").click(grid_details);

    });
</script>

<ul class="nav nav-tabs" data-tabs="tabs" id="maintabs">
    <li class="active"><a data-toggle="tab" id="totals_tab" href="#totals">{{ lang._('Totals') }}</a></li>
    <li><a data-toggle="tab" id="details_tab" href="#details">{{ lang._('Details') }}</a></li>
</ul>
<div class="tab-content content-box tab-content" style="padding: 10px;">
    <div id="totals" class="tab-pane fade in active">
      <div class="pull-right">
        <select class="selectpicker" id="total_time_select">
          <option value="2h">{{ lang._('Last 2 hours, 30 second average') }}</option>
          <option value="8h">{{ lang._('Last 8 hours, 5 minute average') }}</option>
          <option value="1w">{{ lang._('Last week, 1 hour average') }}</option>
          <option value="1m">{{ lang._('Last month, 24 hour average') }}</option>
          <option value="1y">{{ lang._('Last year, 24 hour average') }}</option>
        </select>
      </div>
      <br/>
      <br/>
      <div class="panel panel-primary">
        <div class="panel-heading panel-heading-sm">
          {{ lang._('Interface totals (bits/sec)') }}
        </div>
        <div class="panel-body">
          <div id="chart_intf_in">
            <small>{{ lang._('IN') }}</small>
            <svg style="height:150px;"></svg>
          </div>
          <div id="chart_intf_out">
            <small>{{ lang._('OUT') }}</small>
            <svg style="height:150px;"></svg>
          </div>
        </div>
      </div>
      <div class="panel panel-primary">
        <div class="panel-heading panel-heading-sm">
          {{ lang._('Top usage ports / sources (bytes)') }}
        </div>
        <div class="panel-body">
          <div class="row">
            <div class="col-xs-12">
              <select class="selectpicker" id="interface_select">
              </select>
            </div>
            <div class="col-xs-12 col-sm-6">
              <div id="chart_top_ports">
                <svg style="height:300px;"></svg>
              </div>
            </div>
            <div class="col-xs-12 col-sm-6">
              <div id="chart_top_sources">
                <svg style="height:300px;"></svg>
              </div>
            </div>
          </div>
          <div class="col-xs-12">
            <small>{{ lang._('click on pie for details') }}</small>
          </div>

        </div>
      </div>
    </div>
    <div id="details" class="tab-pane fade in">
      <table class="table table-condensed">
        <thead>
          <tr>
            <th>{{ lang._('Date (from/to)') }}</th>
            <th>{{ lang._('Interface') }}</th>
            <th>{{ lang._('(dst) Port') }}</th>
            <th>{{ lang._('(src) Address') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td>
              <select class="selectpicker" id="date_detail_from"  data-live-search="true" data-size="10">
              </select>
              <select class="selectpicker" id="date_detail_to"  data-live-search="true" data-size="10">
              </select>
            </td>
            <td>
              <select class="selectpicker" id="interface_select_detail">
              </select>
            </td>
            <td><input type="text" id="service_port_detail"></td>
            <td><input type="text" id="address_detail"></td>
            <td><button id="refresh_details" type="button" class="btn glyphicon glyphicon-refresh"></button></td>
          </tr>
        </tbody>
      </table>
      <br/>
      <table class="table table-condensed table-striped" id="netflow_details">
        <thead>
          <tr>
            <th>{{ lang._('Service') }}</th>
            <th>{{ lang._('Source') }}</th>
            <th>{{ lang._('Destination') }}</th>
            <th>{{ lang._('Bytes') }}</th>
            <th>{{ lang._('Last seen') }}</th>
            <th>%</th>
          </tr>
        </thead>
        <tbody>
        </tbody>
        <tfoot>
          <tr>
            <td colspan="3">{{ lang._('Total (selection)') }}</td>
            <td id="netflow_details_total"></td>
          </tr>
        </tfoot>
      </table>
    </div>
</div>