# UFW-Easy
### 1. 安装
```bash
sudo bash -c 'wget -O /usr/local/bin/ufw-easy https://raw.githubusercontent.com/Lanlan13-14/UFW-Easy/main/ufw_easy.sh && chmod +x /usr/local/bin/ufw-easy && ufw-easy'
```
### 已安装？执行
```
sudo ufw-easy
```
### 卸载
###### 本步骤已集成于ufw-easy可直接输入ufw-easy选择11运行，效果与此处卸载脚本一致
```
sudo bash -c "$(curl -sL https://raw.githubusercontent.com/Lanlan13-14/UFW-Easy/main/uninstall.sh)"
```

### 2. 添加规则
1. 选择 "2. 添加简单规则" 或 "3. 添加高级规则"
2. 添加所需规则（会自动插入到规则列表开头）

### 3. 应用规则
1. 选择 "7. 启用防火墙并应用规则"
2. 系统将启用 UFW 并应用所有规则
3. 查看最终规则顺序确认优先级

### 4. 验证规则
1. 选择 "1. 显示防火墙状态和规则"
2. 确认自定义规则在默认拒绝策略之前

## 重要说明

1. **规则优先级**：后添加的规则会出现在规则列表前面（优先级更高）
2. **默认策略**：入站默认拒绝所有，出站默认允许所有
3. **规则生效**：所有规则变更需手动启用防火墙后才生效
4. **规则顺序**：使用 `show_status` 查看规则顺序确认优先级
5. **如果没有安装UFW会默认安装**

## 特别感谢
### [bqlpfy](https://github.com/bqlpfy/ssr)

