function [C,XML] = cat_io_colormaps(Cname,ncolors)
% _________________________________________________________________________
% Create CAT Colormaps.
%
%   [C,XML] = cat_io_colormaps(Cname,ncolors)
%
%   Cname   = ['marks' | 'marks+' | 'BCGWHw' | 'BGWHn'];
%   ncolors =
% _________________________________________________________________________
% $Id$
  
  % number of colors:
  if ~exist('Cname','var')
    Cname = 'marks+';
  end
  if ~exist('ncolors','var')
    ncolors = [];
  else 
    if ncolors<1   
      error('MATLAB:cat_io_colormaps','Need at least one Color');
    elseif ncolors>2^12
      error('MATLAB:cat_io_colormaps', ...
       'Wow, why do you want to create a rainbow???. Please use less colors or chagne me.\n');
    end
  end
  
  
  % load basic colormap
  switch Cname
    case 'marks+', 
      C = [ 
            0.0000    0.4000    0.0000  % 0 - excellent (dark green)
            0.0000    0.8000    0.0000  % 1 - excellent (light green)
            0.4000    0.6000    0.1000  % 2 - good      (yellow-green)
            1.0000    0.6000    0.4000  % 3 - ok        (yellow-orange)
            1.0000    0.3000    0.0000  % 4 - bad       (red-orange)
            0.8000    0.2000    0.0000  % 5 - very bad  (red)
            0.7000    0.0000    0.0000  % 6 - unusable  (dark red)
            0.6000    0.0000    0.0000  % 7 - unusable  (dark red)
            0.5000    0.0000    0.0000  % 8 - unusable  (dark red)
            0.4000    0.0000    0.0000  % 9 - unusable  (dark red)
          ];
    case 'marks',
      C = [ %JET
            0.0000    0.0000    0.5625  % 4 - -3              (dark blue)
            0.0000    0.0000    1.0000  % 3 - -2              (blue)
            0.0000    1.0000    1.0000  % 2 - -1              (cyan)
            0.0000    1.0000    0.0000  % 1 -  0 normal case  (green)
            1.0000    1.0000    0.0000  % 2 - +1              (yellow)
            1.0000    0.0000    0.0000  % 3 - +2              (red)
            0.5104    0.0000    0.0000  % 4 - +3              (dark red)
          ];
    % vbm-output
    % GMT output
    % ...
    case 'magentadk'
      C = [0.95 0.95 0.95; 0.7 0.2 0.7];
    case 'magenta'
      C = [0.95 0.95 0.95; 1.0 0.4 1.0];
    case 'orange'
      C = [0.95 0.95 0.95; 0.8 0.4 0.6];
    case 'blue'
      C = blue;
    case 'BCGWHw'
      C = BCGWHw;
    case 'BCGWHwov'
      C = BCGWHwov;
    case 'BCGWHn'
      C = BCGWHn;
    case 'BCGWHn2';
      C = BCGWHnov;
    case 'BCGWHgov'
      C = BCGWHgov;
    case 'BCGWHnov'
      C = BCGWHnov;
    case 'BCGWHcheckcov'
      C = BCGWHcheckcov;
    case 'curvature';
      C = [ 
            0.9900    0.9900    0.9900 
            0.9500    0.9000    0.8000 
            0.9700    0.8500    0.6000 
            1.0000    0.8000    0.3000 
            1.0000    0.6000    0.0000 
            1.0000    0.3000    0.0000 
            1.0000    0.0000    0.0000  
            0.5000    0.0000    0.0000  
            0.0000    0.0000    0.0000  
          ];
    case 'hotinv';
      C = hotinv;
    case 'hot';
      C = hotinv; C = C(end:-1:1,:);
    case 'cold';
      C = hotinv; C = C(end:-1:1,:); C = [C(:,3),C(:,2),C(:,1)];
    case 'coldinv';
      C = hotinv; C = [C(:,3),C(:,2),C(:,1)];
    case 'BWR';
      CR = hotinv; 
      CB = [CR(:,3),CR(:,2),CR(:,1)]; CB = CB(end:-1:1,:);
      C  = [CB;CR(2:end,:,:,:)];
    otherwise, error('MATLAB:cat_io_colormaps','Unknown Colormap ''%s''\n',Cname);
  end
  if isempty(ncolors), ncolors = size(C,1); end
  
  % interpolate colormap
  if size(C,1)~=ncolors;
    ss    = (size(C,1)-1)/(ncolors);
    [X,Y] = meshgrid(1:ss:size(C,1)-ss,1:3);
    C     = interp2(1:size(C,1),1:3,C',X,Y)'; 
    XML   = cellstr([ dec2hex(round(min(255,max(0,C(:,1)*255)))), ...
             dec2hex(round(min(255,max(0,C(:,2)*255)))), ...
             dec2hex(round(min(255,max(0,C(:,3)*255)))) ]);
  end
 
  
end
function C=hotinv
  C = [ 
    0.9900    0.9900    0.9900 
    0.9500    0.9000    0.6000 
    1.0000    0.8000    0.3000 
    1.0000    0.6000    0.0000 
    1.0000    0.3000    0.0000 
    1.0000    0.0000    0.0000  
    0.5000    0.0000    0.0000  
    0.0000    0.0000    0.0000  
  ]; 
end
function C=BCGWHcheckcov
  C = [ 
         0         0         0
    0.0131    0.0281    0.0915
    0.0261    0.0562    0.1830
    0.0392    0.0843    0.2745
    0.0523    0.1124    0.3660
    0.0654    0.1405    0.4575
    0.0784    0.1686    0.5490
    0.1221    0.2437    0.6134
    0.1658    0.3188    0.6779
    0.2095    0.3938    0.7423
    0.2532    0.4689    0.8067
    0.2969    0.5440    0.8711
    0.3406    0.6190    0.9356
    0.3843    0.6941    1.0000
    0.3494    0.7219    0.9091
    0.3144    0.7497    0.8182
    0.2795    0.7775    0.7273
    0.2446    0.8053    0.6364
    0.2096    0.8332    0.5455
    0.1747    0.8610    0.4545
    0.1398    0.8888    0.3636
    0.1048    0.9166    0.2727
    0.0699    0.9444    0.1818
    0.0349    0.9722    0.0909
         0    1.0000         0
    0.1667    1.0000         0
    0.3333    1.0000         0
    0.5000    1.0000         0
    0.6667    1.0000         0
    0.8333    1.0000         0
    1.0000    1.0000         0
    1.0000    0.8333         0
    1.0000    0.6667         0
    1.0000    0.5000         0
    1.0000    0.3333         0
    1.0000    0.1667         0
    1.0000         0         0
    1.0000    0.0621    0.0719
    1.0000    0.1242    0.1438
    1.0000    0.1863    0.2157
    1.0000    0.2484    0.2876
    1.0000    0.3105    0.3595
    1.0000    0.3725    0.4314
    1.0000    0.4346    0.5033
    1.0000    0.4967    0.5752
    1.0000    0.5588    0.6471
    1.0000    0.6209    0.7190
    1.0000    0.6830    0.7908
    1.0000    0.7451    0.8627
    0.9663    0.7077    0.8424
    0.9325    0.6703    0.8220
    0.8988    0.6329    0.8016
    0.8651    0.5956    0.7812
    0.8314    0.5582    0.7608
    0.7976    0.5208    0.7404
    0.7639    0.4834    0.7200
    0.7302    0.4460    0.6996
    0.6965    0.4086    0.6792
    0.6627    0.3712    0.6588
    0.6290    0.3339    0.6384
    0.5953    0.2965    0.6180
    0.5616    0.2591    0.5976
    0.5278    0.2217    0.5773
    0.4941    0.1843    0.5569
  ]; 
end
function C=BCGWHgov
C = [
         0.95    0.95      0.95
         0.5    0.5        0.95
         0    0.5         1
         0    1         0.5
         0.5    1.0000         0
    0.4000    0.4000         0
    0.8000         0         0
    0.9000    0.4314    0.4627
    1.0000    0.8627    0.9255
    1.0000    0.4314    0.9627
    1.0000         0    1.0000
    ...0.7882         0    1.0000
    1              1    1.0000
    0.7882         0    1.0000
  ];
end
function C=BCGWHnov
C = [
         0         0         0
    ...0.0174    0.4980    0.7403
    ...0.8084    0.9216    1.0000
    ...0.6784    0.9216    1.0000
         0.0    0.05        .5
         0.0    0.4         1  % CSF
         0.0    0.7        0.1 %
         0    0.9500         0 % GM
    1.0000    1.0000         0 % 
    0.8000         0         0 % WM
    0.9000    0.4314    0.4627
    1.0000    0.8627    0.9255
    1.0000    0.4314    0.9627
    1.0000         1    1.0000
    0.7882         1    1.0000
    1              1    1.0000
  ];
end
function C=BCGWHn
  C = [
    0.0392    0.1412    0.4157
    0.0349    0.2366    0.4806
    0.0305    0.3320    0.5455
    0.0261    0.4275    0.6105
    0.0218    0.5229    0.6754
    0.0174    0.6183    0.7403
    0.0131    0.7137    0.8052
    0.0087    0.8092    0.8702
    0.0044    0.9046    0.9351
         0    1.0000    1.0000
         0    0.9163    0.8333
         0    0.8327    0.6667
         0    0.7490    0.5000
         0    0.6653    0.3333
         0    0.5817    0.1667
         0    0.4980         0
         0    0.5984         0
         0    0.6988         0
         0    0.7992         0
         0    0.8996         0
         0    1.0000         0
    0.3333    1.0000         0
    0.6667    1.0000         0
    1.0000    1.0000         0
    1.0000    0.8902         0
    1.0000    0.7804         0
    1.0000    0.6706         0
    1.0000    0.5608         0
    1.0000    0.4510         0
    0.9333    0.3007         0
    0.8667    0.1503         0
    0.8000         0         0
    0.8154    0.0462    0.0603
    0.8308    0.0923    0.1207
    0.8462    0.1385    0.1810
    0.8615    0.1846    0.2413
    0.8769    0.2308    0.3017
    0.8923    0.2769    0.3620
    0.9077    0.3231    0.4223
    0.9231    0.3692    0.4827
    0.9385    0.4154    0.5430
    0.9538    0.4615    0.6033
    0.9692    0.5077    0.6637
    0.9846    0.5538    0.7240
    1.0000    0.6000    0.7843
    0.9974    0.6214    0.7935
    0.9948    0.6429    0.8026
    0.9922    0.6643    0.8118
    0.9895    0.6858    0.8209
    0.9869    0.7072    0.8301
    0.9843    0.7286    0.8392
    0.9817    0.7501    0.8484
    0.9791    0.7715    0.8575
    0.9765    0.7929    0.8667
    0.9739    0.8144    0.8758
    0.9712    0.8358    0.8850
    0.9686    0.8573    0.8941
    0.9660    0.8787    0.9033
    0.9634    0.9001    0.9124
    0.9608    0.9216    0.9216
  ]; 
end
function C=BCGWHnov_old
  C = [
    0.0392    0.1412    0.4157
    0.0349    0.2366    0.4806
    0.0305    0.3320    0.5455
    0.0261    0.4275    0.6105
    0.0218    0.4980    0.6754
    0.0174    0.4980    0.7403
    0.0131    0.4980    0.8052
    0.0087    0.4980    0.8702
    0.0044    0.4980    0.9351
         0    0.4980    1.0000
         0    0.4980    0.8333
         0    0.4980    0.6667
         0    0.4980    0.5000
         0    0.4980    0.3333
         0    0.4980    0.1667
         0    0.4980         0
         0    0.6117         0
         0    0.7255         0
         0    0.8392         0
         0    0.9529         0
         0    1.0000         0
    0.2405    0.9608    0.0013
    0.4810    0.9216    0.0026
    0.7216    0.8824    0.0039
    0.8608    0.9412    0.0020
    1.0000    1.0000         0
    1.0000    0.8588         0
    1.0000    0.6549         0
    1.0000    0.4510         0
    0.9000    0.2255         0
    0.8000         0         0
    0.8200    0.0600    0.0784
    0.8400    0.1200    0.1569
    0.8600    0.1800    0.2353
    0.8800    0.2400    0.3137
    0.9000    0.3000    0.3922
    0.9200    0.3600    0.4706
    0.9400    0.4200    0.5490
    0.9600    0.4800    0.6274
    0.9800    0.5400    0.7059
    1.0000    0.6000    0.7843
    0.9749    0.5400    0.7808
    0.9498    0.4800    0.7772
    0.9247    0.4200    0.7737
    0.8996    0.3600    0.7702
    0.8745    0.3000    0.7667
    0.8494    0.2400    0.7631
    0.8243    0.1800    0.7596
    0.7992    0.1200    0.7561
    0.7741    0.0600    0.7525
    0.7490         0    0.7490
    0.7102         0    0.7102
    0.6714         0    0.6714
    0.6327         0    0.6327
    0.5939         0    0.5939
    0.5551         0    0.5551
    0.5163         0    0.5163
    0.4776         0    0.4776
    0.4388         0    0.4388
    0.4000         0    0.4000
         0         0         0
   ];
end
function C=BCGWHw
  C = [
    1.0000    1.0000    1.0000
    0.9741    0.9843    0.9961
    0.9482    0.9686    0.9922
    0.9224    0.9530    0.9882
    0.8965    0.9373    0.9843
    0.8706    0.9216    0.9804
    0.8322    0.9216    0.9843
    0.7937    0.9216    0.9882
    0.7553    0.9216    0.9922
    0.7168    0.9216    0.9961
    0.6784    0.9216    1.0000
    0.5686    0.8470    0.8882
    0.4588    0.7725    0.7765
    0.3059    0.6810    0.5177
    0.1529    0.5895    0.2588
         0    0.4980         0
         0    0.5984         0
         0    0.6988         0
         0    0.7992         0
         0    0.8996         0
         0    1.0000         0
    0.2500    1.0000         0
    0.5000    1.0000         0
    0.7500    1.0000         0
    1.0000    1.0000         0
    1.0000    0.8627         0
    1.0000    0.7255         0
    1.0000    0.5882         0
    1.0000    0.4510         0
    0.9333    0.3007         0
    0.8667    0.1503         0
    0.8000         0         0
    0.8500    0.1000    0.2000
    0.9000    0.2000    0.4000
    0.9500    0.3000    0.6000
    1.0000    0.4000    0.8000
    1.0000    0.4672    0.8286
    1.0000    0.5345    0.8571
    1.0000    0.6017    0.8857
    1.0000    0.6689    0.9143
    1.0000    0.7361    0.9429
    1.0000    0.8034    0.9714
    1.0000    0.8706    1.0000
    0.9500    0.7868    1.0000
    0.9000    0.7029    1.0000
    0.8500    0.6191    1.0000
    0.8000    0.5353    1.0000
    0.7500    0.4515    1.0000
    0.7000    0.3676    1.0000
    0.6500    0.2838    1.0000
    0.6000    0.2000    1.0000
    0.5250    0.1750    1.0000
    0.4500    0.1500    1.0000
    0.3750    0.1250    1.0000
    0.3000    0.1000    1.0000
    0.2250    0.0750    1.0000
    0.1500    0.0500    1.0000
    0.0750    0.0250    1.0000
         0         0    1.0000
         0         0         0
  ]; 
end
function C=BCGWHwov
  C = [
    1.0000    1.0000    1.0000
    0.9741    0.9843    0.9961
    0.9482    0.9686    0.9922
    0.9224    0.9530    0.9882
    0.8965    0.9373    0.9843
    0.8706    0.9216    0.9804
    0.8225    0.9216    0.9853
    0.7745    0.9216    0.9902
    0.7264    0.9216    0.9951
    0.6784    0.9216    1.0000
    0.6052    0.8719    0.9255
    0.5320    0.8222    0.8510
    0.4588    0.7725    0.7765
    0.2294    0.6352    0.3882
         0    0.4980         0
         0    0.6117         0
         0    0.7255         0
         0    0.8392         0
         0    0.9529         0
         0    1.0000         0
    0.2405    0.9608    0.0013
    0.4810    0.9216    0.0026
    0.7216    0.8824    0.0039
    0.8608    0.9412    0.0020
    1.0000    1.0000         0
    1.0000    0.8588         0
    1.0000    0.6549         0
    1.0000    0.4510         0
    0.9000    0.2255         0
    0.8000         0         0
    0.8200    0.0600    0.0784
    0.8400    0.1200    0.1569
    0.8600    0.1800    0.2353
    0.8800    0.2400    0.3137
    0.9000    0.3000    0.3922
    0.9200    0.3600    0.4706
    0.9400    0.4200    0.5490
    0.9600    0.4800    0.6274
    0.9800    0.5400    0.7059
    1.0000    0.6000    0.7843
    0.9749    0.5400    0.7808
    0.9498    0.4800    0.7772
    0.9247    0.4200    0.7737
    0.8996    0.3600    0.7702
    0.8745    0.3000    0.7667
    0.8494    0.2400    0.7631
    0.8243    0.1800    0.7596
    0.7992    0.1200    0.7561
    0.7741    0.0600    0.7525
    0.7490         0    0.7490
    0.7102         0    0.7102
    0.6714         0    0.6714
    0.6327         0    0.6327
    0.5939         0    0.5939
    0.5551         0    0.5551
    0.5163         0    0.5163
    0.4776         0    0.4776
    0.4388         0    0.4388
    0.4000         0    0.4000
         0         0         0
   ];
end
function C = blue
  C = [
    0.02  0.25  0.50
    0.20  0.45  0.75
    0.40  0.80  0.95
    0.80  0.95  0.98
    0.94  0.96  0.99
    ];
end