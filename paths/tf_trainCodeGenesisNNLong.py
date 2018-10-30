# Python Code that uses Tensorflow to Train the NNs for Longitudinal Controller 
# Monimoy Bujarbaruah: 10/28/2018
# No Rights Reserved

import numpy as np
import matplotlib.pyplot as plt
import tensorflow as tf
import scipy.io as sio
#import h5py

#%% We have imported all dependencies
df = sio.loadmat('NN_test_trainingDataLong10k_PrimalDual2.mat',squeeze_me=True, struct_as_record=False) # read data set using pandas
x_data = df['inputParam_long']
y_data = df['outputParamDacc_long']
y_dataDual = df['outputParamDual_long']

#f = h5py.File('NN_test_trainingDataLong10k_PrimalDual.mat')
#x_data = np.array(f['inputParam_long'])
#y_data =  np.array(f['outputParamDacc_long'])
#y_dataDual =  np.array(f['outputParamDual_long'])

data_length = x_data.shape[0]
train_length = int(np.floor(data_length*4/5))                           # 80% data to train 

## Split Training and Testing Data to not Overfit 
x_train = x_data[:train_length, :]                      # Training data
y_train = y_data[:train_length,:]                       # Training data
y_trainDual = y_dataDual[:train_length,:]               # Training data 

x_test = x_data[train_length:, :]                       # Testing data
y_test = y_data[train_length:,:]                        # Testing data
y_testDual = y_dataDual[train_length:,:]                # Testing data 

insize =  x_data.shape[1]
outsize = y_data.shape[1]                               # Dimension of primal output data 
outsizeD = y_dataDual.shape[1]                          # Dimension of dual output data 

xs = tf.placeholder("float")
ys = tf.placeholder("float")
ysD = tf.placeholder("float")
#%%

################## PRIMAL NN TRAINING ##############################
neuron_size = 30
neuron_sizeML = neuron_size                             # Can vary size of the intermediate layer as well

W_1 = tf.Variable(tf.random_uniform([insize,neuron_size]))
b_1 = tf.Variable(tf.random_uniform([neuron_size]))
layer_1 = tf.add(tf.matmul(xs,W_1), b_1)
layer_1 = tf.nn.relu(layer_1)

# layer 1 multiplying and adding bias then activation function
W_2 = tf.Variable(tf.random_uniform([neuron_size,neuron_sizeML]))
b_2 = tf.Variable(tf.random_uniform([neuron_sizeML]))
layer_2 = tf.add(tf.matmul(layer_1,W_2), b_2)
layer_2 = tf.nn.relu(layer_2)


# layer 2 multiplying and adding bias then activation function
W_O = tf.Variable(tf.random_uniform([neuron_sizeML,outsize]))
b_O = tf.Variable(tf.random_uniform([outsize]))
output = tf.add(tf.matmul(layer_2,W_O), b_O)

#  O/p layer multiplying and adding bias then activation function
#  notice output layer has one node only since performing #regression

cost = tf.reduce_mean(tf.square(output-ys))            # our mean squared error cost function
train = tf.train.AdamOptimizer(0.001).minimize(cost)  # GD and proximal GD working bad! Adam and RMS well.

c_t = []
c_test = []
#%%
with tf.Session() as sess:
     # Initiate session and initialize all vaiables
     sess.run(tf.global_variables_initializer())
     saver = tf.train.Saver()

     inds = np.arange(x_train.shape[0])
     train_count = len(x_train)

     N_EPOCHS = 500
     BATCH_SIZE = 32

     for i in range(0, N_EPOCHS):
         for start, end in zip(range(0, train_count, BATCH_SIZE),
                               range(BATCH_SIZE, train_count + 1,BATCH_SIZE)):

             sess.run([cost,train], feed_dict={xs: x_train[start:end],
                                            ys: y_train[start:end]})
    
         c_t.append(sess.run(cost, feed_dict={xs:x_train,ys:y_train}))
         c_test.append(sess.run(cost, feed_dict={xs:x_test,ys:y_test}))
         print('Epoch :',i,'Cost Train :',c_t[i], 'Cost Test :',c_test[i])
#%% Saving weight matrices 
     vj={}
     vj['W1'] = sess.run(W_1)
     vj['W2'] = sess.run(W_2)
     vj['W0'] = sess.run(W_O)
     vj['b1'] = sess.run(b_1)
     vj['b2'] = sess.run(b_2)
     vj['b0'] = sess.run(b_O)
     sio.savemat('trained_weightsPrimalLong.mat',vj)

#%%         
################################ Plotting the Primal NN Train Quality
plt.plot(range(len(c_t)),c_t, 'r')
plt.ylabel('Error in Training')
plt.xlabel('Epoch')
plt.title('Fitting Error Training')
plt.show()
# plt.hold(True)                                          # hold is on
plt.plot(range(len(c_test)),c_test, 'b')
plt.ylabel('Error in Testing Points')
plt.xlabel('Epoch')
plt.title('Fitting Testing Error')
plt.show()
#%%
########################## PRIMAL TRAIN ENDS. DUAL TRAIN START 
# neuron_sizeD = 30
# neuron_sizeMLD = neuron_sizeD                             # Can vary size of the intermediate layer as well

# W_1D = tf.Variable(tf.random_uniform([insize,neuron_sizeD]))
# b_1D = tf.Variable(tf.random_uniform([neuron_sizeD]))
# layer_1D = tf.add(tf.matmul(xs,W_1D), b_1D)
# layer_1D = tf.nn.relu(layer_1D)

# # layer 1 multiplying and adding bias then activation function
# W_2D = tf.Variable(tf.random_uniform([neuron_sizeD,neuron_sizeMLD]))
# b_2D = tf.Variable(tf.random_uniform([neuron_sizeMLD]))
# layer_2D = tf.add(tf.matmul(layer_1D,W_2D), b_2D)
# layer_2D = tf.nn.relu(layer_2D)

# # layer 2 multiplying and adding bias then activation function
# W_OD = tf.Variable(tf.random_uniform([neuron_sizeMLD,outsizeD]))
# b_OD = tf.Variable(tf.random_uniform([outsizeD]))
# outputD = tf.add(tf.matmul(layer_2D,W_OD), b_OD)

# #  O/p layer multiplying and adding bias then activation function
# #  notice output layer has one node only since performing #regression

# costD = tf.reduce_mean(tf.square(outputD-ysD))           # our mean squared error cost function
# trainD = tf.train.AdamOptimizer(0.0001).minimize(costD)  # GD and proximal GD working bad! Adam and RMS well.

# c_tD = []
# c_testD = []
# #%%
# with tf.Session() as sess:
#      # Initiate session and initialize all vaiables
#      sess.run(tf.global_variables_initializer())
#      saver = tf.train.Saver()

#      inds = np.arange(x_train.shape[0])
#      train_count = len(x_train)

#      N_EPOCHS = 2000
#      BATCH_SIZE = 64

#      for i in range(0, N_EPOCHS):
#          for start, end in zip(range(0, train_count, BATCH_SIZE),
#                                range(BATCH_SIZE, train_count + 1,BATCH_SIZE)):

#              sess.run([costD,trainD], feed_dict={xs: x_train[start:end],
#                                             ysD: y_trainDual[start:end]})
    
#          c_tD.append(sess.run(costD, feed_dict={xs:x_train,ysD:y_trainDual}))
#          c_testD.append(sess.run(costD, feed_dict={xs:x_test,ysD:y_testDual}))
#          print('Epoch :',i,'Cost Train Dual :',c_tD[i], 'Cost Test Dual:',c_testD[i])

# #%%
# #  Getting the variables from the Neural Nets
#      vjD={}
#      vjD['W1D'] = sess.run(W_1D)
#      vjD['W2D'] = sess.run(W_2D)
#      vjD['W0D'] = sess.run(W_OD)
#      vjD['b1D'] = sess.run(b_1D)
#      vjD['b2D'] = sess.run(b_2D)
#      vjD['b0D'] = sess.run(b_OD)
#      sio.savemat('trained_weightsDualLong.mat',vjD)

# #%%
# ################################## Plotting the Dual NN Train Quality
# plt.plot(range(len(c_tD)),c_tD, 'r')
# plt.ylabel('Error in Training')
# plt.xlabel('Epoch')
# plt.title('Fitting Error Training')
# plt.show()
# # plt.hold(True)                                          # hold is on
# plt.plot(range(len(c_testD)),c_testD, 'b')
# plt.ylabel('Error in Testing Points')
# plt.xlabel('Epoch')
# plt.title('Fitting Testing Error')
# plt.show()


