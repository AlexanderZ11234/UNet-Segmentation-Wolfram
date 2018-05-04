(* ::Package:: *)

(* ::Section:: *)
(*Creating  UNet*)


convolutionModule[kernelsize_,padsize_,stride_]:=NetChain[
 {ConvolutionLayer[1,kernelsize,"Stride"-> stride,"PaddingSize"-> padsize],
 BatchNormalizationLayer[],
 ElementwiseLayer[Ramp]}
];


decoderModule[kernelsize_,padsize_,stride_]:= NetChain[
 {DeconvolutionLayer[1,{2,2},"PaddingSize"-> 0,"Stride"->{2, 2}],
 BatchNormalizationLayer[],
 ElementwiseLayer[Ramp],
 convolutionModule[kernelsize,padsize,stride]}
];


encodeModule[kernelsize_,padsize_,stride_]:=NetAppend[
 convolutionModule[kernelsize,padsize,stride],
 PoolingLayer[{2,2},"Function"-> Max,"Stride"-> {2,2}]
];


cropLayer[{dim1_,dim2_}]:=NetChain[
 {PartLayer[{1,1;;dim1,1;;dim2}],
 ReshapeLayer[{1,dim1,dim2}]}
];


nodeGraphMXNET[net_,opt: ("MXNetNodeGraph"|"MXNetNodeGraphPlot")]:= net~NetInformation~opt;


UNET:=Block[{kernelsize = {3,3},padsize = {1,1},stride={1,1}},
NetGraph[
 <|"enc_1"->encodeModule[kernelsize,0,stride],
 "enc_2"->encodeModule[kernelsize,padsize,stride],
 "enc_3"->encodeModule[kernelsize,padsize,stride],
 "enc_4"->encodeModule[kernelsize,padsize,stride],
 "dropout_1"->DropoutLayer[],
 "enc_5"-> encodeModule[kernelsize,padsize,stride],
 "dec_1"-> decoderModule[kernelsize,padsize,stride],
 "dec_2"->decoderModule[kernelsize,padsize+1,stride],
 "crop_1" ->cropLayer[{20,20}],
 "concat_1" -> CatenateLayer[],
 "dropout_2" -> DropoutLayer[],
 "conv_1"-> convolutionModule[kernelsize,padsize,stride],
 "dec_3"->decoderModule[kernelsize,padsize,stride],
 "crop_2" ->cropLayer[{40,40}],
 "concat_2" -> CatenateLayer[],
 "dropout_3" -> DropoutLayer[],
 "conv_2"-> convolutionModule[kernelsize,padsize,stride],
 "dec_4"->decoderModule[kernelsize,padsize,stride],
 "crop_3" ->cropLayer[{80,80}],
 "concat_3" -> CatenateLayer[],
 "dropout_4" -> DropoutLayer[],
 "conv_3"-> convolutionModule[kernelsize,padsize,stride],
 "dec_5"->decoderModule[kernelsize,padsize,stride],
 "map" -> {ConvolutionLayer[1,kernelsize,"Stride"-> stride,"PaddingSize"-> padsize],LogisticSigmoid}|>,
{{NetPort["Input"]->"enc_1"->"enc_2"-> "enc_3"-> "enc_4"->"dropout_1"-> "enc_5"->"dec_1"-> "dec_2"},
"dec_2"-> "crop_1",
{"enc_3","crop_1"}-> "concat_1"-> "dropout_2"-> "conv_1"-> "dec_3",
"enc_2"-> "crop_2",
{"crop_2","dec_3"}-> "concat_2"-> "dropout_3"-> "conv_2"-> "dec_4",
"enc_1"-> "crop_3",
{"crop_3","dec_4"}-> "concat_3"-> "dropout_4"-> "conv_3"-> "dec_5"-> "map"
},
"Input"->NetEncoder[{"Image",{168,168},ColorSpace->"Grayscale"}],
"Output"->NetDecoder[{"Image",Automatic,ColorSpace->"Grayscale"}]
]
]//NetInitialize


(* ::Section:: *)
(*Training UNet*)


(* ::Input:: *)
(*(* images/masks need to be resized and shuffled *)*)


trainNet[net_,dirImages_, dirMasks_, batchsize_: 8, maxtrainRounds_: 100]:=Module[{images,shuffledimages,keysshuffle,masks,shuffledmasks,
dataset,validationset,unseen,labeldataset,labelvalidationset,groundTruth,trainedNN},
 SetDirectory[dirImages];
 images = ImageResize[Import[dir<>"\\"<>#],{168,168}]&/@FileNames[];
 shuffledimages=RandomSample@Thread[Range@Length@images ->images];
 keysshuffle=Keys@shuffledimages;
 SetDirectory[dirMasks];
 masks=Binarize[ImageResize[Import[dir<>"\\"<>#],{160,160}]]&/@FileNames[];
 shuffledmasks=Lookup[<|Thread[Range@Length@masks -> masks]|>,keysshuffle];
 {dataset,validationset,unseen}=TakeList[Values@shuffledimages,{290,80,20}];
 {labeldataset,labelvalidationset,groundTruth}=TakeList[shuffledmasks,{290,80,20}];
 trainedNN=NetTrain[net,Thread[dataset->labeldataset], ValidationSet->Thread[validationset-> labelvalidationset],
  BatchSize->batchsize,MaxTrainingRounds->maxtrainRounds, TargetDevice->"GPU"];
 {trainedNN,unseen,groundTruth}
]
