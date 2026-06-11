
```
camel run traces-mapper.camel.yaml logs-mapper.camel.yaml infinispan.camel.yaml kaoto-datamapper-*
```

```
camel export --runtime=quarkus --directory=./quarkus traces-mapper.camel.yaml logs-mapper.camel.yaml infinispan.camel.yaml kaoto-datamapper-*
```

```
camel export --runtime=spring-boot --directory=./springboot traces-mapper.camel.yaml logs-mapper.camel.yaml infinispan.camel.yaml kaoto-datamapper-*
camel kubernetes export --runtime=spring-boot --directory=./springboot traces-mapper.camel.yaml logs-mapper.camel.yaml infinispan.camel.yaml kaoto-datamapper-*
```
