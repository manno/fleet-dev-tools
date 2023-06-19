#!/bin/bash
#
# grep all resources in all namespaces for text

key="${1-fleet}"

kubectl api-resources --verbs=list --namespaced=true -o name | head | while read -r res 2> /dev/null; do
  kubectl get --ignore-not-found -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' -A "$res" 2> /dev/null | while read -r ns name; do
    #echo "$res $namespace $name"
    if kubectl get --ignore-not-found -o yaml -n "$ns" "$res" "$name" | grep -q "$key"; then
      echo "--"
      echo -e "\e[32m$res - $ns/$name:\e[0m"
      kubectl get --ignore-not-found -o yaml -n "$ns" "$res" "$name" | grep --color "$key"
      echo "--"
    fi
  done
done

kubectl api-resources --verbs=list --namespaced=false -o name | head | while read -r res 2> /dev/null; do
  kubectl get --ignore-not-found -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' "$res" 2> /dev/null | while read -r name; do
    #echo "$res $name"
    if kubectl get --ignore-not-found -o yaml "$res" "$name" | grep -q "$key"; then
      echo "--"
      echo -e "\e[32m$res - $name:\e[0m"
      kubectl get --ignore-not-found -o yaml "$res" "$name" | grep -n --color "$key"
      echo "--"
    fi
  done
done
